// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockAavePool} from "../../src/mocks/MockAavePool.sol";
import {MockCompoundMarket} from "../../src/mocks/MockCompoundMarket.sol";
import {AaveLikeAdapter} from "../../src/adapters/AaveLikeAdapter.sol";
import {RescueExecutor} from "../../src/reprieve/RescueExecutor.sol";
import {ReprieveTypes} from "../../src/reprieve/libs/ReprieveTypes.sol";

/**
 * @title SameChainRescueSetup
 * @notice Setup-only phase for same-chain rescue scenarios.
 * @dev Creates user source/target positions and writes artifact for later use.
 */
contract SameChainRescueSetup is Script {
    function run() external {
        uint256 ownerPk = vm.envUint("PRIVATE_KEY");
        uint256 workflowPk = vm.envOr("WORKFLOW_PRIVATE_KEY", ownerPk);
        uint256 userPk = vm.envOr("USER_PRIVATE_KEY", ownerPk);
        uint256 minterPk = vm.envOr("MINTER_PRIVATE_KEY", ownerPk);

        address owner = vm.addr(ownerPk);
        address workflow = vm.addr(workflowPk);
        address user = vm.addr(userPk);

        address rescueExecutorAddr = vm.envAddress("RESCUE_EXECUTOR");
        address aavePoolAddr = vm.envAddress("AAVE_POOL");
        address compoundMarketAddr = vm.envAddress("COMPOUND_MARKET");
        address aaveAdapterAddr = vm.envAddress("AAVE_ADAPTER");
        address compoundAdapterAddr = vm.envAddress("COMPOUND_ADAPTER");
        address collateralAsset = vm.envAddress("COLLATERAL_ASSET");
        address debtAsset = vm.envAddress("DEBT_ASSET");
        string memory rescueModeRaw = vm.envOr("RESCUE_MODE", string("TOP_UP"));
        ReprieveTypes.RescueMode rescueMode = _parseMode(rescueModeRaw);

        uint256 userCollateralMint = vm.envOr("USER_COLLATERAL_MINT", uint256(25 ether));
        uint256 sourceSupply = vm.envOr("SOURCE_SUPPLY_COLLATERAL", uint256(10 ether));
        uint256 targetSupply = vm.envOr("TARGET_SUPPLY_COLLATERAL", uint256(8 ether));
        uint256 targetBorrow = vm.envOr("TARGET_BORROW_DEBT", uint256(5_000e6));
        uint256 engineLiquidityDebt = vm.envOr("ENGINE_LIQUIDITY_DEBT", uint256(100_000e6));
        uint256 repaySourceDebtMint = vm.envOr("REPAY_SOURCE_DEBT_MINT", uint256(20_000e6));
        uint256 repaySourceSupplyDebt = vm.envOr("REPAY_SOURCE_SUPPLY_DEBT", uint256(10_000e6));
        uint256 repaySourceEngineLiquidityCollateral = vm.envOr("REPAY_SOURCE_ENGINE_LIQ_COLLATERAL", uint256(1_000 ether));

        MockERC20 collateral = MockERC20(collateralAsset);
        MockERC20 debt = MockERC20(debtAsset);
        MockAavePool aavePool = MockAavePool(aavePoolAddr);
        MockCompoundMarket compoundMarket = MockCompoundMarket(compoundMarketAddr);
        RescueExecutor executor = RescueExecutor(payable(rescueExecutorAddr));

        address sourceAdapterForStep = aaveAdapterAddr;
        address sourceAssetForStep = collateralAsset;
        address sourcePoolForStep = aavePoolAddr;
        address targetAdapterForStep = compoundAdapterAddr;

        console.log("Same-chain rescue setup on chain:", block.chainid);
        console.log("Owner:", owner);
        console.log("Workflow:", workflow);
        console.log("User:", user);
        console.log("Mode:", rescueMode == ReprieveTypes.RescueMode.TOP_UP ? "TOP_UP" : "REPAY");

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

        // 3) User creates target position
        vm.startBroadcast(userPk);
        collateral.approve(compoundMarketAddr, type(uint256).max);
        compoundMarket.mint(collateralAsset, targetSupply);
        compoundMarket.borrow(debtAsset, targetBorrow);
        vm.stopBroadcast();

        if (rescueMode == ReprieveTypes.RescueMode.TOP_UP) {
            // Source leg: lend collateral / borrow debt market; withdraw collateral later for top-up.
            vm.startBroadcast(userPk);
            collateral.approve(aavePoolAddr, type(uint256).max);
            aavePool.supply(collateralAsset, sourceSupply, user, 0);
            aavePool.aToken().approve(aaveAdapterAddr, type(uint256).max);
            vm.stopBroadcast();
        } else {
            // Source leg for repay mode: opposite leg used to source debt token for repay.
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
            sourcePoolForStep = address(repaySourcePool);
        }

        _writeArtifact(
            rescueModeRaw,
            rescueExecutorAddr,
            sourcePoolForStep,
            sourceAdapterForStep,
            sourceAssetForStep,
            targetAdapterForStep,
            collateralAsset,
            debtAsset,
            user
        );

        console.log("Setup complete.");
        console.log("Source pool:", sourcePoolForStep);
        console.log("Source adapter:", sourceAdapterForStep);
        console.log("Target adapter:", targetAdapterForStep);
        console.log("Source asset:", sourceAssetForStep);
    }

    function _writeArtifact(
        string memory rescueModeRaw,
        address rescueExecutorAddr,
        address sourcePool,
        address sourceAdapter,
        address sourceAsset,
        address targetAdapter,
        address collateralAsset,
        address debtAsset,
        address user
    ) internal {
        string memory path = string.concat("config/same-chain-rescue-setup-", vm.toString(block.chainid), ".json");
        string memory out = string.concat(
            '{"chainId":',
            vm.toString(block.chainid),
            ',"mode":"',
            rescueModeRaw,
            '","setup":{"user":"',
            vm.toString(user),
            '","rescueExecutor":"',
            vm.toString(rescueExecutorAddr),
            '","sourcePool":"',
            vm.toString(sourcePool),
            '","sourceAdapter":"',
            vm.toString(sourceAdapter),
            '","sourceAsset":"',
            vm.toString(sourceAsset),
            '","targetAdapter":"',
            vm.toString(targetAdapter),
            '","collateralAsset":"',
            vm.toString(collateralAsset),
            '","debtAsset":"',
            vm.toString(debtAsset),
            '"}}'
        );
        vm.writeFile(path, out);
        console.log("Artifact written:", path);
    }

    function _parseMode(string memory raw) internal pure returns (ReprieveTypes.RescueMode) {
        bytes32 modeHash = keccak256(bytes(raw));
        if (modeHash == keccak256(bytes("TOP_UP"))) {
            return ReprieveTypes.RescueMode.TOP_UP;
        }
        if (modeHash == keccak256(bytes("REPAY"))) {
            return ReprieveTypes.RescueMode.REPAY;
        }
        revert("SameChainRescueSetup: RESCUE_MODE must be TOP_UP or REPAY");
    }
}
