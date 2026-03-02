// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockAavePool} from "../../src/mocks/MockAavePool.sol";
import {MockCompoundMarket} from "../../src/mocks/MockCompoundMarket.sol";
import {AaveLikeAdapter} from "../../src/adapters/AaveLikeAdapter.sol";
import {RescueExecutor} from "../../src/reprieve/RescueExecutor.sol";
import {RescueLog} from "../../src/reprieve/RescueLog.sol";
import {ReprieveTypes} from "../../src/reprieve/libs/ReprieveTypes.sol";

/**
 * @title RunSameChainRescue
 * @notice Runs a same-chain rescue scenario against deployed demo lending + Reprieve contracts.
 * @dev Expects owner rights for wiring and token mint permissions for setup.
 */
contract RunSameChainRescue is Script {
    function run() external {
        uint256 ownerPk = vm.envUint("PRIVATE_KEY");
        uint256 workflowPk = vm.envOr("WORKFLOW_PRIVATE_KEY", ownerPk);
        uint256 userPk = vm.envOr("USER_PRIVATE_KEY", ownerPk);
        uint256 minterPk = vm.envOr("MINTER_PRIVATE_KEY", ownerPk);

        address owner = vm.addr(ownerPk);
        address workflow = vm.addr(workflowPk);
        address user = vm.addr(userPk);

        address rescueExecutorAddr = vm.envAddress("RESCUE_EXECUTOR");
        address rescueLogAddr = vm.envOr("RESCUE_LOG", address(0));
        address aavePoolAddr = vm.envAddress("AAVE_POOL");
        address compoundMarketAddr = vm.envAddress("COMPOUND_MARKET");
        address aaveAdapter = vm.envAddress("AAVE_ADAPTER");
        address compoundAdapter = vm.envAddress("COMPOUND_ADAPTER");
        address collateralAsset = vm.envAddress("COLLATERAL_ASSET");
        address debtAsset = vm.envAddress("DEBT_ASSET");
        string memory rescueModeRaw = vm.envOr("RESCUE_MODE", string("TOP_UP"));
        ReprieveTypes.RescueMode rescueMode = _parseMode(rescueModeRaw);

        uint256 userCollateralMint = vm.envOr("USER_COLLATERAL_MINT", uint256(25 ether));
        uint256 sourceSupply = vm.envOr("SOURCE_SUPPLY_COLLATERAL", uint256(10 ether));
        uint256 targetSupply = vm.envOr("TARGET_SUPPLY_COLLATERAL", uint256(8 ether));
        uint256 targetBorrow = vm.envOr("TARGET_BORROW_DEBT", uint256(5_000e6));
        uint256 defaultWithdrawAmount = rescueMode == ReprieveTypes.RescueMode.REPAY ? uint256(2_000e6) : uint256(5 ether);
        uint256 sourceWithdrawAmount = vm.envOr("RESCUE_WITHDRAW_COLLATERAL", defaultWithdrawAmount);
        uint256 rescueTopUpAmount = vm.envOr("RESCUE_TOPUP_COLLATERAL", sourceWithdrawAmount);
        uint256 rescueDebtAmount = vm.envOr("RESCUE_REPAY_DEBT", uint256(2_000e6));
        uint256 engineLiquidityDebt = vm.envOr("ENGINE_LIQUIDITY_DEBT", uint256(100_000e6));
        uint256 repaySourceDebtMint = vm.envOr("REPAY_SOURCE_DEBT_MINT", uint256(20_000e6));
        uint256 repaySourceSupplyDebt = vm.envOr("REPAY_SOURCE_SUPPLY_DEBT", uint256(10_000e6));
        uint256 repaySourceEngineLiquidityCollateral = vm.envOr("REPAY_SOURCE_ENGINE_LIQ_COLLATERAL", uint256(1_000 ether));

        MockERC20 collateral = MockERC20(collateralAsset);
        MockERC20 debt = MockERC20(debtAsset);
        MockAavePool aavePool = MockAavePool(aavePoolAddr);
        MockCompoundMarket compoundMarket = MockCompoundMarket(compoundMarketAddr);
        RescueExecutor executor = RescueExecutor(payable(rescueExecutorAddr));

        bytes32 execId = keccak256(abi.encodePacked("same-chain-rescue", block.chainid, user, block.timestamp));

        console.log("Running same-chain rescue on chain:", block.chainid);
        console.log("Owner:", owner);
        console.log("Workflow:", workflow);
        console.log("User:", user);
        console.log("Mode:", rescueMode == ReprieveTypes.RescueMode.TOP_UP ? "TOP_UP" : "REPAY");
        console.log("ExecId:", vm.toString(execId));

        // 1) Owner wiring for operator/workflow path
        vm.startBroadcast(ownerPk);
        executor.setAuthorizedWorkflow(workflow, true);
        compoundMarket.engine().setAuthorizedOperator(compoundMarketAddr, true);
        if (rescueMode == ReprieveTypes.RescueMode.TOP_UP) {
            aavePool.engine().setAuthorizedOperator(aavePoolAddr, true);
        }
        vm.stopBroadcast();

        // 2) Seed balances/liquidity required for scenario
        vm.startBroadcast(minterPk);
        collateral.mint(user, userCollateralMint);
        debt.mint(address(compoundMarket.engine()), engineLiquidityDebt);
        if (rescueMode == ReprieveTypes.RescueMode.REPAY) {
            debt.mint(user, repaySourceDebtMint);
        }
        vm.stopBroadcast();

        // 3) User creates source and target positions
        vm.startBroadcast(userPk);
        collateral.approve(compoundMarketAddr, type(uint256).max);
        compoundMarket.mint(collateralAsset, targetSupply);
        compoundMarket.borrow(debtAsset, targetBorrow);
        vm.stopBroadcast();

        address sourceAdapterForStep = aaveAdapter;
        address sourceAssetForStep = collateralAsset;
        uint256 sourceAmountForStep = rescueTopUpAmount;
        uint256 debtAmountForStep = 0;

        if (rescueMode == ReprieveTypes.RescueMode.TOP_UP) {
            vm.startBroadcast(userPk);
            collateral.approve(aavePoolAddr, type(uint256).max);
            aavePool.supply(collateralAsset, sourceSupply, user, 0);
            aavePool.aToken().approve(aaveAdapter, type(uint256).max);
            vm.stopBroadcast();
        } else {
            if (sourceWithdrawAmount < rescueDebtAmount) {
                revert("RunSameChainRescue: RESCUE_WITHDRAW_COLLATERAL must be >= RESCUE_REPAY_DEBT in REPAY mode");
            }

            vm.startBroadcast(ownerPk);
            MockAavePool repaySourcePool =
                new MockAavePool(debtAsset, collateralAsset, aavePool.oracle(), owner);
            AaveLikeAdapter repaySourceAdapter =
                new AaveLikeAdapter(address(repaySourcePool), debtAsset, collateralAsset, owner);
            repaySourcePool.engine().setAuthorizedOperator(address(repaySourcePool), true);
            vm.stopBroadcast();

            vm.startBroadcast(minterPk);
            collateral.mint(address(repaySourcePool.engine()), repaySourceEngineLiquidityCollateral);
            vm.stopBroadcast();

            vm.startBroadcast(userPk);
            debt.approve(address(repaySourcePool), type(uint256).max);
            repaySourcePool.supply(debtAsset, repaySourceSupplyDebt, user, 0);
            repaySourcePool.aToken().approve(address(repaySourceAdapter), type(uint256).max);
            vm.stopBroadcast();

            sourceAdapterForStep = address(repaySourceAdapter);
            sourceAssetForStep = debtAsset;
            sourceAmountForStep = sourceWithdrawAmount;
            debtAmountForStep = rescueDebtAmount;

            console.log("Repay source pool:", address(repaySourcePool));
            console.log("Repay source adapter:", address(repaySourceAdapter));
        }

        uint256 collateralBefore = compoundMarket.getUserPosition(user).collateral;
        uint256 debtBefore = compoundMarket.getUserPosition(user).debt;

        // 4) Workflow executes same-chain rescue
        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](1);
        steps[0] = ReprieveTypes.RescueStep({
            stepIndex: 0,
            sourceAdapter: sourceAdapterForStep,
            targetAdapter: compoundAdapter,
            collateralAsset: sourceAssetForStep,
            debtAsset: debtAsset,
            collateralAmount: sourceAmountForStep,
            debtAmount: debtAmountForStep,
            isCrossChain: false,
            targetChain: 0
        });

        ReprieveTypes.RescuePlan memory plan = ReprieveTypes.RescuePlan({
            execId: execId,
            user: user,
            mode: rescueMode,
            steps: steps,
            deadline: block.timestamp + 1 hours,
            maxFee: 0
        });

        vm.startBroadcast(workflowPk);
        bool ok = executor.executeRescue(plan);
        vm.stopBroadcast();

        uint256 collateralAfter = compoundMarket.getUserPosition(user).collateral;
        uint256 debtAfter = compoundMarket.getUserPosition(user).debt;
        console.log("Rescue success:", ok);
        console.log("Target collateral before:", collateralBefore);
        console.log("Target collateral after :", collateralAfter);
        console.log("Target debt before:", debtBefore);
        console.log("Target debt after :", debtAfter);
        console.log("Rescue status enum:", uint256(executor.getRescueStatus(execId)));

        if (rescueLogAddr != address(0)) {
            console.log("Rescue log entries:", RescueLog(rescueLogAddr).getLogEntryCount(execId));
        }
    }

    function _parseMode(string memory raw) internal pure returns (ReprieveTypes.RescueMode) {
        bytes32 modeHash = keccak256(bytes(raw));
        if (modeHash == keccak256(bytes("TOP_UP"))) {
            return ReprieveTypes.RescueMode.TOP_UP;
        }
        if (modeHash == keccak256(bytes("REPAY"))) {
            return ReprieveTypes.RescueMode.REPAY;
        }
        revert("RunSameChainRescue: RESCUE_MODE must be TOP_UP or REPAY");
    }
}
