// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AdapterRegistry} from "../../src/reprieve/AdapterRegistry.sol";
import {RescueLog} from "../../src/reprieve/RescueLog.sol";
import {RescueEscrow} from "../../src/reprieve/RescueEscrow.sol";
import {RescueExecutor} from "../../src/reprieve/RescueExecutor.sol";
import {CCIPReceiver} from "../../src/reprieve/CCIPReceiver.sol";
import {HealthMonitor} from "../../src/reprieve/HealthMonitor.sol";
import {IAdapterRegistry} from "../../src/reprieve/interfaces/IAdapterRegistry.sol";
import {IRescueLog} from "../../src/reprieve/interfaces/IRescueLog.sol";
import {IRescueEscrow} from "../../src/reprieve/interfaces/IRescueEscrow.sol";
import {IRescueExecutor} from "../../src/reprieve/interfaces/IRescueExecutor.sol";
import {ICCIPReceiver} from "../../src/reprieve/interfaces/ICCIPReceiver.sol";

/**
 * @title DumpAbiHashes
 * @notice Emits deterministic ABI/code drift fingerprints for Reprieve contracts.
 * @dev Uses creation bytecode hashes and selector-set hashes for quick review in CI.
 */
contract DumpAbiHashes is Script {
    function run() external pure {
        console.log("=== Reprieve Contract Creation Code Hashes ===");
        _printHash("AdapterRegistry", keccak256(type(AdapterRegistry).creationCode));
        _printHash("RescueLog", keccak256(type(RescueLog).creationCode));
        _printHash("RescueEscrow", keccak256(type(RescueEscrow).creationCode));
        _printHash("RescueExecutor", keccak256(type(RescueExecutor).creationCode));
        _printHash("CCIPReceiver", keccak256(type(CCIPReceiver).creationCode));
        _printHash("HealthMonitor", keccak256(type(HealthMonitor).creationCode));

        console.log("\n=== Interface Selector-Set Hashes ===");
        _printHash("IAdapterRegistry", _hashIAdapterRegistry());
        _printHash("IRescueLog", _hashIRescueLog());
        _printHash("IRescueEscrow", _hashIRescueEscrow());
        _printHash("IRescueExecutor", _hashIRescueExecutor());
        _printHash("ICCIPReceiver", _hashICCIPReceiver());
    }

    function _printHash(string memory label, bytes32 hash_) internal pure {
        console.log(label, vm.toString(hash_));
    }

    function _pack(bytes4[] memory selectors) internal pure returns (bytes memory out) {
        for (uint256 i = 0; i < selectors.length; i++) {
            out = abi.encodePacked(out, selectors[i]);
        }
    }

    function _hashIAdapterRegistry() internal pure returns (bytes32) {
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = IAdapterRegistry.setAdapter.selector;
        selectors[1] = IAdapterRegistry.getAdapter.selector;
        selectors[2] = IAdapterRegistry.setSupportedProtocol.selector;
        return keccak256(_pack(selectors));
    }

    function _hashIRescueLog() internal pure returns (bytes32) {
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = IRescueLog.logRescueInitiated.selector;
        selectors[1] = IRescueLog.logRescueStep.selector;
        selectors[2] = IRescueLog.logRescueCompleted.selector;
        selectors[3] = IRescueLog.logRescueFailed.selector;
        selectors[4] = IRescueLog.getLogEntries.selector;
        return keccak256(_pack(selectors));
    }

    function _hashIRescueEscrow() internal pure returns (bytes32) {
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = IRescueEscrow.depositFailedTransfer.selector;
        selectors[1] = IRescueEscrow.claimEscrow.selector;
        selectors[2] = IRescueEscrow.retryTransfer.selector;
        selectors[3] = IRescueEscrow.getEscrow.selector;
        selectors[4] = IRescueEscrow.canClaim.selector;
        return keccak256(_pack(selectors));
    }

    function _hashIRescueExecutor() internal pure returns (bytes32) {
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = IRescueExecutor.executeRescue.selector;
        selectors[1] = IRescueExecutor.executeSameChainLeg.selector;
        selectors[2] = IRescueExecutor.completeCrossChainLeg.selector;
        selectors[3] = IRescueExecutor.rescueInProgress.selector;
        selectors[4] = IRescueExecutor.getRescueStatus.selector;
        selectors[5] = IRescueExecutor.authorizedWorkflows.selector;
        selectors[6] = IRescueExecutor.setAuthorizedWorkflow.selector;
        selectors[7] = IRescueExecutor.setCcipExtraArgs.selector;
        return keccak256(_pack(selectors));
    }

    function _hashICCIPReceiver() internal pure returns (bytes32) {
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = ICCIPReceiver.ccipReceive.selector;
        selectors[1] = ICCIPReceiver.setExecutor.selector;
        selectors[2] = ICCIPReceiver.setRouter.selector;
        selectors[3] = ICCIPReceiver.setAllowedSourceChain.selector;
        selectors[4] = ICCIPReceiver.setAllowedSender.selector;
        selectors[5] = ICCIPReceiver.getExecutor.selector;
        selectors[6] = ICCIPReceiver.getRouter.selector;
        selectors[7] = ICCIPReceiver.isAllowedSourceChain.selector;
        selectors[8] = ICCIPReceiver.isAllowedSender.selector;
        return keccak256(_pack(selectors));
    }
}
