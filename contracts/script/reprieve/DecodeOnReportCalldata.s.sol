// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ReprieveTypes} from "../../src/reprieve/libs/ReprieveTypes.sol";

/**
 * @title DecodeOnReportCalldata
 * @notice Decodes raw calldata for `onReport(bytes metadata, bytes report)`.
 * @dev Run with:
 *      ONREPORT_CALLDATA=0x... forge script script/reprieve/DecodeOnReportCalldata.s.sol:DecodeOnReportCalldata -vvvv
 */
contract DecodeOnReportCalldata is Script {
    function run() external view {
        string memory calldataHex = vm.envString("ONREPORT_CALLDATA");
        bytes memory raw = vm.parseBytes(calldataHex);

        require(raw.length >= 4, "DecodeOnReportCalldata: calldata too short");

        bytes4 selector = _selector(raw);
        bytes4 expected = bytes4(keccak256("onReport(bytes,bytes)"));

        console.log("Decoding onReport calldata");
        console.log("Total bytes:", raw.length);
        console.log("Selector:", vm.toString(selector));
        console.log("Expected:", vm.toString(expected));
        console.log("Selector match:", selector == expected);

        bytes memory argsData = _slice(raw, 4, raw.length - 4);
        (bytes memory metadata, bytes memory report) = abi.decode(argsData, (bytes, bytes));

        _logMetadata(metadata);
        _logReport(report);
    }

    function _logMetadata(bytes memory metadata) internal view {
        console.log("---- Metadata ----");
        console.log("Length:", metadata.length);
        console.log("Raw:", vm.toString(metadata));

        if (metadata.length < 62) {
            console.log("Packed metadata too short for workflowId+workflowName+workflowOwner");
            return;
        }

        bytes32 workflowId;
        bytes10 workflowName;
        address workflowOwner;
        assembly {
            let start := add(metadata, 32)
            workflowId := mload(start)
            workflowName := mload(add(start, 32))
            workflowOwner := shr(96, mload(add(start, 42)))
        }

        console.log("workflowId:", vm.toString(workflowId));
        console.log("workflowName(bytes10):", vm.toString(workflowName));
        console.log("workflowName(ascii):", _bytes10ToAscii(workflowName));
        console.log("workflowOwner:", workflowOwner);
    }

    function _logReport(bytes memory report) internal view {
        console.log("---- Report ----");
        console.log("Length:", report.length);
        console.log("Raw:", vm.toString(report));

        ReprieveTypes.RescuePlan memory plan = abi.decode(report, (ReprieveTypes.RescuePlan));

        console.log("execId:", vm.toString(plan.execId));
        console.log("user:", plan.user);
        console.log("mode:", _modeToString(plan.mode));
        console.log("deadline:", plan.deadline);
        console.log("maxFee:", plan.maxFee);
        console.log("steps:", plan.steps.length);

        for (uint256 i = 0; i < plan.steps.length; i++) {
            ReprieveTypes.RescueStep memory step = plan.steps[i];
            console.log("---- Step ----");
            console.log("index:", step.stepIndex);
            console.log("sourceAdapter:", step.sourceAdapter);
            console.log("targetAdapter:", step.targetAdapter);
            console.log("collateralAsset:", step.collateralAsset);
            console.log("debtAsset:", step.debtAsset);
            console.log("collateralAmount:", step.collateralAmount);
            console.log("debtAmount:", step.debtAmount);
            console.log("isCrossChain:", step.isCrossChain);
            console.log("targetChain:", uint256(step.targetChain));
        }
    }

    function _selector(bytes memory raw) internal pure returns (bytes4 out) {
        assembly {
            out := mload(add(raw, 32))
        }
    }

    function _slice(bytes memory data, uint256 start, uint256 len) internal pure returns (bytes memory out) {
        require(start + len <= data.length, "slice out of bounds");
        out = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            out[i] = data[start + i];
        }
    }

    function _modeToString(ReprieveTypes.RescueMode mode) internal pure returns (string memory) {
        if (mode == ReprieveTypes.RescueMode.TOP_UP) return "TOP_UP";
        if (mode == ReprieveTypes.RescueMode.REPAY) return "REPAY";
        return "UNKNOWN";
    }

    function _bytes10ToAscii(bytes10 value) internal pure returns (string memory) {
        bytes memory out = new bytes(10);
        uint256 length = 0;
        for (uint256 i = 0; i < 10; i++) {
            bytes1 ch = value[i];
            if (ch == 0x00) break;
            out[length] = ch;
            length++;
        }
        bytes memory trimmed = new bytes(length);
        for (uint256 j = 0; j < length; j++) {
            trimmed[j] = out[j];
        }
        return string(trimmed);
    }
}

