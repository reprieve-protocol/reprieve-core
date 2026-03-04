// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockCCIPRouter} from "../../src/mocks/MockCCIPRouter.sol";
import {MockAavePool} from "../../src/mocks/MockAavePool.sol";
import {MockCompoundMarket} from "../../src/mocks/MockCompoundMarket.sol";
import {RescueExecutor} from "../../src/reprieve/RescueExecutor.sol";
import {ReprieveTypes} from "../../src/reprieve/libs/ReprieveTypes.sol";

/**
 * @title RunCrossChainRescue
 * @notice Runs cross-chain rescue initiation and optional mock-delivery flow.
 * @dev Supports local/mock end-to-end by setting MOCK_CCIP_ROUTER and DELIVER_MOCK=true.
 */
contract RunCrossChainRescue is Script {
    function run() external {
        uint256 ownerPk = vm.envUint("PRIVATE_KEY");
        uint256 workflowPk = vm.envOr("WORKFLOW_PRIVATE_KEY", ownerPk);
        uint256 userPk = vm.envOr("USER_PRIVATE_KEY", ownerPk);
        uint256 minterPk = vm.envOr("MINTER_PRIVATE_KEY", ownerPk);
        uint256 bridgeAdminPk = vm.envOr("BRIDGE_ADMIN_PRIVATE_KEY", minterPk);

        address owner = vm.addr(ownerPk);
        address workflow = vm.addr(workflowPk);
        address user = vm.addr(userPk);

        address sourceExecutorAddr = vm.envAddress("SOURCE_EXECUTOR");
        address sourceAavePoolAddr = vm.envAddress("SOURCE_AAVE_POOL");
        address sourceAaveAdapter = vm.envAddress("SOURCE_AAVE_ADAPTER");
        address targetAdapter = vm.envAddress("TARGET_ADAPTER");
        address collateralAsset = vm.envAddress("COLLATERAL_ASSET");
        address debtAsset = vm.envAddress("DEBT_ASSET");
        uint64 destSelector = uint64(vm.envUint("DEST_CHAIN_SELECTOR"));
        uint64 sourceSelector = uint64(vm.envOr("SOURCE_CHAIN_SELECTOR", uint256(0)));
        address destReceiver = vm.envAddress("DEST_RECEIVER");

        address mockRouterAddr = vm.envOr("MOCK_CCIP_ROUTER", address(0));
        address destCompoundMarketAddr = vm.envOr("DEST_COMPOUND_MARKET", address(0));
        string memory rescueModeRaw = vm.envOr("RESCUE_MODE", string("TOP_UP"));
        ReprieveTypes.RescueMode rescueMode = _parseMode(rescueModeRaw);

        uint256 userCollateralMint = vm.envOr("USER_COLLATERAL_MINT", uint256(20 ether));
        uint256 sourceSupply = vm.envOr("SOURCE_SUPPLY_COLLATERAL", uint256(10 ether));
        uint256 crossTransferAmount = vm.envOr("CROSS_TRANSFER_COLLATERAL", uint256(4 ether));
        uint256 crossTopUpAmount = vm.envOr("CROSS_TOPUP_COLLATERAL", crossTransferAmount);
        uint256 crossDebtAmount = vm.envOr("CROSS_REPAY_DEBT", crossTransferAmount);
        uint256 nativeFeeBuffer = vm.envOr("EXECUTOR_NATIVE_FEE_BUFFER", uint256(0.05 ether));
        bool setupTargetDebt = vm.envOr("SETUP_TARGET_DEBT", true);
        bool deliverMock = vm.envOr("DELIVER_MOCK", false);
        bool forceDstDeadlineFail = vm.envOr("FORCE_DST_DEADLINE_FAIL", false);
        bool wireMockBridge = vm.envOr("WIRE_MOCK_BRIDGE", true);
        address bridgeSourceToken = vm.envOr("MOCK_BRIDGE_SOURCE_TOKEN", collateralAsset);
        address bridgeDestinationToken =
            vm.envOr("MOCK_BRIDGE_DEST_TOKEN", rescueMode == ReprieveTypes.RescueMode.REPAY ? debtAsset : collateralAsset);

        MockERC20 collateral = MockERC20(collateralAsset);
        MockERC20 debt = MockERC20(debtAsset);
        MockAavePool sourceAavePool = MockAavePool(sourceAavePoolAddr);
        RescueExecutor sourceExecutor = RescueExecutor(payable(sourceExecutorAddr));
        MockCompoundMarket destCompoundMarket =
            destCompoundMarketAddr == address(0) ? MockCompoundMarket(address(0)) : MockCompoundMarket(destCompoundMarketAddr);

        bytes32 execId = keccak256(abi.encodePacked("cross-chain-rescue", block.chainid, user, block.timestamp));

        console.log("Running cross-chain rescue on chain:", block.chainid);
        console.log("Owner:", owner);
        console.log("Workflow:", workflow);
        console.log("User:", user);
        console.log("ExecId:", vm.toString(execId));

        // 1) Owner lane/workflow wiring
        vm.startBroadcast(ownerPk);
        sourceExecutor.setAuthorizedWorkflow(workflow, true);
        sourceExecutor.setTrustedDestinationChain(destSelector, true);
        sourceExecutor.setChainReceiver(destSelector, destReceiver);
        if (mockRouterAddr != address(0)) {
            sourceExecutor.setCcipRouter(mockRouterAddr);
            if (wireMockBridge) {
                require(sourceSelector != 0, "RunCrossChainRescue: SOURCE_CHAIN_SELECTOR required for mock bridge wiring");
                MockCCIPRouter mockRouter = MockCCIPRouter(mockRouterAddr);
                mockRouter.setCurrentChainSelector(sourceSelector);
                mockRouter.setLane(sourceSelector, destSelector, true);
                mockRouter.setTokenMapping(destSelector, bridgeSourceToken, bridgeDestinationToken);
                mockRouter.setReceiver(destSelector, destReceiver);
            }
        }
        sourceAavePool.engine().setAuthorizedOperator(sourceAavePoolAddr, true);
        vm.stopBroadcast();

        if (mockRouterAddr != address(0) && wireMockBridge) {
            vm.startBroadcast(bridgeAdminPk);
            MockERC20(bridgeSourceToken).setBridgeBurner(mockRouterAddr, true);
            MockERC20(bridgeSourceToken).setBridgeMinter(mockRouterAddr, true);
            vm.stopBroadcast();
        }

        // 2) Setup balances/positions
        vm.startBroadcast(minterPk);
        collateral.mint(user, userCollateralMint);
        if (setupTargetDebt && destCompoundMarketAddr != address(0)) {
            debt.mint(address(destCompoundMarket.engine()), 100_000e6);
        }
        vm.stopBroadcast();

        vm.startBroadcast(userPk);
        collateral.approve(sourceAavePoolAddr, type(uint256).max);
        sourceAavePool.supply(collateralAsset, sourceSupply, user, 0);
        sourceAavePool.aToken().approve(sourceAaveAdapter, type(uint256).max);

        if (setupTargetDebt && destCompoundMarketAddr != address(0)) {
            collateral.approve(destCompoundMarketAddr, type(uint256).max);
            destCompoundMarket.mint(collateralAsset, 8 ether);
            destCompoundMarket.borrow(debtAsset, 5_000e6);
        }
        vm.stopBroadcast();

        // 3) Ensure executor has native fee buffer
        vm.startBroadcast(ownerPk);
        (bool sent,) = payable(sourceExecutorAddr).call{value: nativeFeeBuffer}("");
        require(sent, "RunCrossChainRescue: native fee funding failed");
        vm.stopBroadcast();

        // 4) Execute cross-chain rescue
        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](1);
        steps[0] = ReprieveTypes.RescueStep({
            stepIndex: 0,
            sourceAdapter: sourceAaveAdapter,
            targetAdapter: targetAdapter,
            collateralAsset: collateralAsset,
            debtAsset: debtAsset,
            collateralAmount: rescueMode == ReprieveTypes.RescueMode.TOP_UP ? crossTopUpAmount : crossTransferAmount,
            debtAmount: rescueMode == ReprieveTypes.RescueMode.REPAY ? crossDebtAmount : 0,
            isCrossChain: true,
            targetChain: destSelector
        });

        ReprieveTypes.RescuePlan memory plan = ReprieveTypes.RescuePlan({
            execId: execId,
            user: user,
            mode: rescueMode,
            steps: steps,
            deadline: block.timestamp + 1 hours,
            maxFee: nativeFeeBuffer
        });

        vm.startBroadcast(workflowPk);
        bool ok = sourceExecutor.executeRescue(plan);
        vm.stopBroadcast();

        bytes32 messageId = sourceExecutor.getCcipMessageId(execId);
        console.log("Rescue success:", ok);
        console.log("CCIP messageId:", vm.toString(messageId));
        console.log("Rescue status enum:", uint256(sourceExecutor.getRescueStatus(execId)));

        // 5) Optional local/mock delivery
        if (deliverMock) {
            require(mockRouterAddr != address(0), "RunCrossChainRescue: MOCK_CCIP_ROUTER required for DELIVER_MOCK");
            if (forceDstDeadlineFail) {
                vm.warp(block.timestamp + 2 hours);
            }
            MockCCIPRouter(mockRouterAddr).deliverMessage(messageId);
            console.log("Mock CCIP delivery executed.");
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
        revert("RunCrossChainRescue: RESCUE_MODE must be TOP_UP or REPAY");
    }
}
