// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {RescueExecutor} from "../../src/reprieve/RescueExecutor.sol";
import {ReprieveTypes} from "../../src/reprieve/libs/ReprieveTypes.sol";

/**
 * @title CrossChainRescueExecute
 * @notice Phase 3: Execute cross-chain rescue on source chain.
 * @dev Expects source/destination setup phases already completed.
 */
contract CrossChainRescueExecute is Script {
    function run() external {
        uint256 ownerPk = vm.envUint("PRIVATE_KEY");
        uint256 workflowPk = vm.envOr("WORKFLOW_PRIVATE_KEY", ownerPk);
        uint256 userPk = vm.envOr("USER_PRIVATE_KEY", ownerPk);

        address owner = vm.addr(ownerPk);
        address workflow = vm.addr(workflowPk);
        address user = vm.addr(userPk);

        address sourceExecutorAddr = vm.envAddress("SOURCE_EXECUTOR");
        address sourceAaveAdapter = vm.envAddress("SOURCE_AAVE_ADAPTER");
        address targetAdapter = vm.envAddress("TARGET_ADAPTER");
        address collateralAsset = vm.envAddress("COLLATERAL_ASSET");
        address debtAsset = vm.envAddress("DEBT_ASSET");
        address rescueDebtAsset = vm.envOr("RESCUE_DEBT_ASSET", debtAsset);
        uint64 sourceSelector = uint64(vm.envUint("SOURCE_CHAIN_SELECTOR"));
        uint64 destSelector = uint64(vm.envUint("DEST_CHAIN_SELECTOR"));
        address destReceiver = vm.envAddress("DEST_RECEIVER");
        string memory rescueModeRaw = vm.envOr("RESCUE_MODE", string("TOP_UP"));
        ReprieveTypes.RescueMode rescueMode = _parseMode(rescueModeRaw);

        uint256 crossTransferAmount = vm.envOr("CROSS_TRANSFER_COLLATERAL", uint256(4 ether));
        uint256 crossTopUpAmount = vm.envOr("CROSS_TOPUP_COLLATERAL", crossTransferAmount);
        uint256 crossDebtAmount = vm.envOr("CROSS_REPAY_DEBT", crossTransferAmount);
        uint256 nativeFeeBuffer = vm.envOr("EXECUTOR_NATIVE_FEE_BUFFER", uint256(0.05 ether));
        bool configureLaneAtExecute = vm.envOr("CONFIGURE_LANE_AT_EXECUTE", false);

        RescueExecutor sourceExecutor = RescueExecutor(payable(sourceExecutorAddr));
        bytes32 execId = keccak256(abi.encodePacked("cross-chain-rescue", block.chainid, user, block.timestamp));

        console.log("Cross-chain rescue execute on chain:", block.chainid);
        console.log("Owner:", owner);
        console.log("Workflow:", workflow);
        console.log("User:", user);
        console.log("Mode:", rescueMode == ReprieveTypes.RescueMode.TOP_UP ? "TOP_UP" : "REPAY");
        console.log("ExecId:", vm.toString(execId));
        console.log("TargetAdapter:", targetAdapter);
        console.log("RescueDebtAsset:", rescueDebtAsset);

        vm.startBroadcast(ownerPk);
        sourceExecutor.setAuthorizedWorkflow(workflow, true);
        if (configureLaneAtExecute) {
            sourceExecutor.setTrustedDestinationChain(destSelector, true);
            sourceExecutor.setChainReceiver(destSelector, destReceiver);
        }
        (bool sent,) = payable(sourceExecutorAddr).call{value: nativeFeeBuffer}("");
        require(sent, "CrossChainRescueExecute: native fee funding failed");
        vm.stopBroadcast();

        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](1);
        steps[0] = ReprieveTypes.RescueStep({
            stepIndex: 0,
            sourceAdapter: sourceAaveAdapter,
            targetAdapter: targetAdapter,
            collateralAsset: collateralAsset,
            debtAsset: rescueMode == ReprieveTypes.RescueMode.REPAY ? rescueDebtAsset : debtAsset,
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
        console.log("Source selector:", sourceSelector);
        console.log("Destination selector:", destSelector);
        console.log("CCIP messageId:", vm.toString(messageId));
        console.log("Rescue status enum:", uint256(sourceExecutor.getRescueStatus(execId)));
    }

    function _parseMode(string memory raw) internal pure returns (ReprieveTypes.RescueMode) {
        bytes32 modeHash = keccak256(bytes(raw));
        if (modeHash == keccak256(bytes("TOP_UP"))) {
            return ReprieveTypes.RescueMode.TOP_UP;
        }
        if (modeHash == keccak256(bytes("REPAY"))) {
            return ReprieveTypes.RescueMode.REPAY;
        }
        revert("CrossChainRescueExecute: RESCUE_MODE must be TOP_UP or REPAY");
    }
}

