// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {RescueExecutor} from "../../src/reprieve/RescueExecutor.sol";
import {ReprieveTypes} from "../../src/reprieve/libs/ReprieveTypes.sol";

interface IWorkflowReceiverDebug {
    function onReport(bytes calldata metadata, bytes calldata report) external;
    function setForwarderAddress(address forwarder) external;
    function getForwarderAddress() external view returns (address);
    function getExpectedAuthor() external view returns (address);
    function getExpectedWorkflowId() external view returns (bytes32);
    function getExpectedWorkflowName() external view returns (bytes10);
}

contract DebugWorkflowReceiverOnReport is Script {
    struct DebugConfig {
        uint256 ownerPk;
        uint256 senderPk;
        address owner;
        address sender;
        address receiver;
        address executor;
        address user;
        address sourceAdapter;
        address targetAdapter;
        address collateralAsset;
        address debtAsset;
        uint256 collateralAmount;
        uint256 debtAmount;
        bool isCrossChain;
        uint64 targetChain;
        uint256 deadlineSeconds;
        uint256 maxFee;
        bytes32 execId;
        ReprieveTypes.RescueMode mode;
        bool broadcastDebug;
        bool tempSetForwarder;
        bool restoreForwarder;
        bool includeMetadata;
        bool failOnRevert;
        bytes32 metadataWorkflowId;
        bytes10 metadataWorkflowName;
        address metadataWorkflowOwner;
    }

    function run() external {
        DebugConfig memory c = _loadConfig();
        IWorkflowReceiverDebug receiver = IWorkflowReceiverDebug(c.receiver);
        RescueExecutor executor = RescueExecutor(payable(c.executor));

        ReprieveTypes.RescuePlan memory plan = _buildPlan(c);
        bytes memory report = abi.encode(plan);
        bytes memory metadata = c.includeMetadata
            ? abi.encodePacked(c.metadataWorkflowId, c.metadataWorkflowName, c.metadataWorkflowOwner)
            : bytes("");

        address originalForwarder = receiver.getForwarderAddress();
        _logContext(c, receiver, executor, originalForwarder);

        if (c.tempSetForwarder) {
            _setForwarder(receiver, c.ownerPk, c.owner, c.sender, c.broadcastDebug);
        }

        (bool ok, bytes memory retData) = _callOnReport(
            receiver, c.senderPk, c.sender, metadata, report, c.broadcastDebug
        );

        if (c.tempSetForwarder && c.restoreForwarder) {
            _setForwarder(receiver, c.ownerPk, c.owner, originalForwarder, c.broadcastDebug);
        }

        uint256 statusAfter = uint256(executor.getRescueStatus(c.execId));
        console.log("onReport success:", ok);
        if (!ok) {
            console.log("onReport revert selector:", _revertSelectorHex(retData));
            console.log("onReport revert reason:", _decodeRevertReason(retData));
        }
        console.log("Status after:", statusAfter);
        console.log("Current forwarder:", receiver.getForwarderAddress());

        if (!ok && c.failOnRevert) {
            revert("DebugWorkflowReceiverOnReport: onReport reverted");
        }
    }

    function _loadConfig() internal view returns (DebugConfig memory c) {
        c.ownerPk = vm.envUint("PRIVATE_KEY");
        c.senderPk = vm.envOr("REPORT_SENDER_PRIVATE_KEY", c.ownerPk);
        c.owner = vm.addr(c.ownerPk);
        c.sender = vm.addr(c.senderPk);

        c.receiver = vm.envAddress("WORKFLOW_RECEIVER");
        c.executor = vm.envAddress("RESCUE_EXECUTOR");
        c.user = vm.envAddress("RESCUE_USER");
        c.sourceAdapter = vm.envAddress("SOURCE_ADAPTER");
        c.targetAdapter = vm.envAddress("TARGET_ADAPTER");
        c.collateralAsset = vm.envAddress("STEP_COLLATERAL_ASSET");
        c.debtAsset = vm.envAddress("STEP_DEBT_ASSET");

        c.collateralAmount = vm.envUint("STEP_COLLATERAL_AMOUNT");
        c.debtAmount = vm.envOr("STEP_DEBT_AMOUNT", uint256(0));
        c.isCrossChain = vm.envOr("STEP_IS_CROSS_CHAIN", false);
        c.targetChain = uint64(vm.envOr("STEP_TARGET_CHAIN", uint256(0)));
        c.deadlineSeconds = vm.envOr("DEADLINE_SECONDS", uint256(3600));
        c.maxFee = vm.envOr("MAX_FEE_WEI", uint256(0));
        c.mode = _parseMode(vm.envOr("RESCUE_MODE", string("TOP_UP")));

        bytes32 fallbackExecId = keccak256(
            abi.encodePacked("debug-onreport", block.chainid, c.user, uint256(c.mode), block.timestamp)
        );
        c.execId = vm.envOr("EXECUTION_ID", fallbackExecId);

        c.broadcastDebug = vm.envOr("BROADCAST_DEBUG", false);
        c.tempSetForwarder = vm.envOr("TEMP_SET_FORWARDER", true);
        c.restoreForwarder = vm.envOr("RESTORE_FORWARDER", true);
        c.includeMetadata = vm.envOr("INCLUDE_METADATA", true);
        c.failOnRevert = vm.envOr("FAIL_ON_REVERT", false);

        c.metadataWorkflowId = vm.envOr("METADATA_WORKFLOW_ID", bytes32(0));
        c.metadataWorkflowName = _stringToBytes10(vm.envOr("METADATA_WORKFLOW_NAME", string("")));
        c.metadataWorkflowOwner = vm.envOr("METADATA_WORKFLOW_OWNER", c.sender);
    }

    function _buildPlan(DebugConfig memory c) internal view returns (ReprieveTypes.RescuePlan memory plan) {
        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](1);
        steps[0] = ReprieveTypes.RescueStep({
            stepIndex: 0,
            sourceAdapter: c.sourceAdapter,
            targetAdapter: c.targetAdapter,
            collateralAsset: c.collateralAsset,
            debtAsset: c.debtAsset,
            collateralAmount: c.collateralAmount,
            debtAmount: c.debtAmount,
            isCrossChain: c.isCrossChain,
            targetChain: c.targetChain
        });

        plan = ReprieveTypes.RescuePlan({
            execId: c.execId,
            user: c.user,
            mode: c.mode,
            steps: steps,
            deadline: block.timestamp + c.deadlineSeconds,
            maxFee: c.maxFee
        });
    }

    function _logContext(
        DebugConfig memory c,
        IWorkflowReceiverDebug receiver,
        RescueExecutor executor,
        address originalForwarder
    ) internal view {
        console.log("Debug onReport callback");
        console.log("Chain ID:", block.chainid);
        console.log("Receiver:", c.receiver);
        console.log("Executor:", c.executor);
        console.log("ExecId:", vm.toString(c.execId));
        console.log("Mode:", c.mode == ReprieveTypes.RescueMode.TOP_UP ? "TOP_UP" : "REPAY");
        console.log("Report sender:", c.sender);
        console.log("Broadcast debug:", c.broadcastDebug);
        console.log("Temp set forwarder:", c.tempSetForwarder);
        console.log("Restore forwarder:", c.restoreForwarder);
        console.log("Include metadata:", c.includeMetadata);
        console.log("Original forwarder:", originalForwarder);
        console.log("Expected author:", receiver.getExpectedAuthor());
        console.log("Expected workflow id:", vm.toString(receiver.getExpectedWorkflowId()));
        console.log("Expected workflow name (bytes10):", vm.toString(receiver.getExpectedWorkflowName()));
        console.log("Status before:", uint256(executor.getRescueStatus(c.execId)));
    }

    function _callOnReport(
        IWorkflowReceiverDebug receiver,
        uint256 senderPk,
        address sender,
        bytes memory metadata,
        bytes memory report,
        bool broadcastDebug
    ) internal returns (bool ok, bytes memory retData) {
        if (broadcastDebug) {
            vm.startBroadcast(senderPk);
            (ok, retData) = address(receiver).call(
                abi.encodeWithSelector(receiver.onReport.selector, metadata, report)
            );
            vm.stopBroadcast();
            return (ok, retData);
        }

        vm.prank(sender);
        (ok, retData) = address(receiver).call(abi.encodeWithSelector(receiver.onReport.selector, metadata, report));
    }

    function _setForwarder(
        IWorkflowReceiverDebug receiver,
        uint256 ownerPk,
        address owner,
        address forwarder,
        bool broadcastDebug
    ) internal {
        if (broadcastDebug) {
            vm.startBroadcast(ownerPk);
            receiver.setForwarderAddress(forwarder);
            vm.stopBroadcast();
            return;
        }

        vm.prank(owner);
        receiver.setForwarderAddress(forwarder);
    }

    function _parseMode(string memory raw) internal pure returns (ReprieveTypes.RescueMode) {
        bytes32 modeHash = keccak256(bytes(raw));
        if (modeHash == keccak256(bytes("TOP_UP"))) return ReprieveTypes.RescueMode.TOP_UP;
        if (modeHash == keccak256(bytes("REPAY"))) return ReprieveTypes.RescueMode.REPAY;
        revert("DebugWorkflowReceiverOnReport: RESCUE_MODE must be TOP_UP or REPAY");
    }

    function _stringToBytes10(string memory value) internal pure returns (bytes10) {
        bytes memory raw = bytes(value);
        bytes10 out;
        uint256 len = raw.length < 10 ? raw.length : 10;
        for (uint256 i = 0; i < len; i++) {
            out |= bytes10(raw[i] & 0xFF) >> (i * 8);
        }
        return out;
    }

    function _revertSelectorHex(bytes memory revertData) internal pure returns (string memory) {
        if (revertData.length < 4) return "0x00000000";
        bytes4 selector;
        assembly {
            selector := mload(add(revertData, 32))
        }
        return vm.toString(selector);
    }

    function _decodeRevertReason(bytes memory revertData) internal pure returns (string memory) {
        if (revertData.length < 4) return "empty revert data";

        bytes4 selector;
        assembly {
            selector := mload(add(revertData, 32))
        }

        if (selector == 0x08c379a0) {
            bytes memory reasonData = _slice(revertData, 4, revertData.length - 4);
            return abi.decode(reasonData, (string));
        }
        if (selector == 0x4e487b71) {
            bytes memory panicData = _slice(revertData, 4, revertData.length - 4);
            uint256 code = abi.decode(panicData, (uint256));
            return string.concat("panic code: ", _uintToString(code));
        }
        return "custom error (see selector)";
    }

    function _slice(bytes memory data, uint256 start, uint256 len) internal pure returns (bytes memory out) {
        require(start + len <= data.length, "slice out of bounds");
        out = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            out[i] = data[start + i];
        }
    }

    function _uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}

