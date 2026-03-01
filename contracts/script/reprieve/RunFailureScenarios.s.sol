// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {IReprieveAdapter} from "../../src/interfaces/IReprieveAdapter.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockAavePool} from "../../src/mocks/MockAavePool.sol";
import {RescueExecutor} from "../../src/reprieve/RescueExecutor.sol";
import {RescueEscrow} from "../../src/reprieve/RescueEscrow.sol";
import {ReprieveTypes} from "../../src/reprieve/libs/ReprieveTypes.sol";

/**
 * @title RunFailureScenarios
 * @notice Executes source failure branches and checks escrow/lock behavior.
 */
contract RunFailureScenarios is Script {
    function run() external {
        uint256 ownerPk = vm.envUint("PRIVATE_KEY");
        uint256 workflowPk = vm.envOr("WORKFLOW_PRIVATE_KEY", ownerPk);
        uint256 userPk = vm.envOr("USER_PRIVATE_KEY", ownerPk);
        uint256 minterPk = vm.envOr("MINTER_PRIVATE_KEY", ownerPk);

        address owner = vm.addr(ownerPk);
        address workflow = vm.addr(workflowPk);
        address user = vm.addr(userPk);

        address executorAddr = vm.envAddress("RESCUE_EXECUTOR");
        address escrowAddr = vm.envAddress("RESCUE_ESCROW");
        address aavePoolAddr = vm.envAddress("AAVE_POOL");
        address aaveAdapterAddr = vm.envAddress("AAVE_ADAPTER");
        address collateralAsset = vm.envAddress("COLLATERAL_ASSET");
        address debtAsset = vm.envAddress("DEBT_ASSET");
        address fallbackTarget = vm.envOr("FALLBACK_TARGET_ADAPTER", aaveAdapterAddr);

        uint256 setupCollateralMint = vm.envOr("SETUP_COLLATERAL_MINT", uint256(20 ether));
        uint256 sourceSupply = vm.envOr("SETUP_SOURCE_SUPPLY", uint256(10 ether));
        uint256 scenarioAmount = vm.envOr("FAIL_SCENARIO_COLLATERAL", uint256(5 ether));
        uint256 scenarioDebt = vm.envOr("FAIL_SCENARIO_DEBT", uint256(5_000e6));

        RescueExecutor executor = RescueExecutor(payable(executorAddr));
        RescueEscrow escrow = RescueEscrow(escrowAddr);
        MockAavePool aavePool = MockAavePool(aavePoolAddr);
        MockERC20 collateral = MockERC20(collateralAsset);

        console.log("Running failure scenarios on chain:", block.chainid);
        console.log("Owner:", owner);
        console.log("Workflow:", workflow);
        console.log("User:", user);

        // Baseline wiring
        vm.startBroadcast(ownerPk);
        executor.setAuthorizedWorkflow(workflow, true);
        aavePool.engine().setAuthorizedOperator(aavePoolAddr, true);
        vm.stopBroadcast();

        // Scenario 1: Pre-withdraw failure (no user position/approval)
        bytes32 execId1 = keccak256(abi.encodePacked("failure-pre-withdraw", block.chainid, user, block.timestamp));
        ReprieveTypes.RescueStep[] memory step1 = new ReprieveTypes.RescueStep[](1);
        step1[0] = ReprieveTypes.RescueStep({
            stepIndex: 0,
            sourceAdapter: aaveAdapterAddr,
            targetAdapter: fallbackTarget,
            collateralAsset: collateralAsset,
            debtAsset: debtAsset,
            collateralAmount: scenarioAmount,
            debtAmount: scenarioDebt,
            isCrossChain: false,
            targetChain: 0
        });
        ReprieveTypes.RescuePlan memory preWithdrawFail = ReprieveTypes.RescuePlan({
            execId: execId1,
            user: user,
            steps: step1,
            deadline: block.timestamp + 1 hours,
            maxFee: 0
        });

        vm.startBroadcast(workflowPk);
        bool preOk = executor.executeRescue(preWithdrawFail);
        vm.stopBroadcast();
        require(!preOk, "RunFailureScenarios: expected pre-withdraw failure");
        require(!executor.rescueInProgress(user), "RunFailureScenarios: user lock not released after scenario 1");

        // Scenario 2: Post-withdraw repay failure -> escrow
        vm.startBroadcast(minterPk);
        collateral.mint(user, setupCollateralMint);
        vm.stopBroadcast();

        vm.startBroadcast(userPk);
        collateral.approve(aavePoolAddr, type(uint256).max);
        aavePool.supply(collateralAsset, sourceSupply, user, 0);
        aavePool.aToken().approve(aaveAdapterAddr, type(uint256).max);
        vm.stopBroadcast();

        vm.startBroadcast(ownerPk);
        FailingAdapter failingTarget = new FailingAdapter();
        vm.stopBroadcast();

        bytes32 execId2 = keccak256(abi.encodePacked("failure-post-withdraw", block.chainid, user, block.timestamp));
        ReprieveTypes.RescueStep[] memory step2 = new ReprieveTypes.RescueStep[](1);
        step2[0] = ReprieveTypes.RescueStep({
            stepIndex: 0,
            sourceAdapter: aaveAdapterAddr,
            targetAdapter: address(failingTarget),
            collateralAsset: collateralAsset,
            debtAsset: debtAsset,
            collateralAmount: scenarioAmount,
            debtAmount: scenarioDebt,
            isCrossChain: false,
            targetChain: 0
        });
        ReprieveTypes.RescuePlan memory postWithdrawFail = ReprieveTypes.RescuePlan({
            execId: execId2,
            user: user,
            steps: step2,
            deadline: block.timestamp + 1 hours,
            maxFee: 0
        });

        uint256 escrowsBefore = escrow.getUserEscrowCount(user);
        vm.startBroadcast(workflowPk);
        bool postOk = executor.executeRescue(postWithdrawFail);
        vm.stopBroadcast();
        uint256 escrowsAfter = escrow.getUserEscrowCount(user);

        require(!postOk, "RunFailureScenarios: expected post-withdraw failure");
        require(!executor.rescueInProgress(user), "RunFailureScenarios: user lock not released after scenario 2");
        require(escrowsAfter > escrowsBefore, "RunFailureScenarios: expected escrow record");

        console.log("Scenario 1 success (expected fail path):", !preOk);
        console.log("Scenario 2 success (expected fail path):", !postOk);
        console.log("Escrows before:", escrowsBefore);
        console.log("Escrows after :", escrowsAfter);
    }
}

contract FailingAdapter is IReprieveAdapter {
    function discoverPositions(address) external pure returns (Position[] memory positions) {
        positions = new Position[](0);
    }

    function healthFactor(address) external pure returns (uint256 hfWad) {
        hfWad = type(uint256).max;
    }

    function availableCollateral(address, address) external pure returns (uint256 amount) {
        amount = 100 ether;
    }

    function getDebt(address, address) external pure returns (uint256 amount) {
        amount = 0;
    }

    function withdrawForRescue(address, address, uint256, address) external pure {}

    function repayForRescue(address, address, uint256) external pure {
        revert("FailingAdapter: forced repay failure");
    }

    function supportsPair(address, address) external pure returns (bool supported) {
        supported = true;
    }

    function protocolName() external pure returns (string memory name) {
        name = "FailingAdapter";
    }

    function protocolAddress() external view returns (address) {
        return address(this);
    }
}
