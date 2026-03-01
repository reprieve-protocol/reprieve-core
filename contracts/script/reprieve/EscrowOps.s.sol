// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {RescueEscrow} from "../../src/reprieve/RescueEscrow.sol";
import {ReprieveTypes} from "../../src/reprieve/libs/ReprieveTypes.sol";

/**
 * @title EscrowOps
 * @notice Utility script for inspect/claim/retry operations on RescueEscrow records.
 * @dev Modes via ESCROW_OP: inspect | claim | retry.
 */
contract EscrowOps is Script {
    function run() external {
        address escrowAddr = vm.envAddress("RESCUE_ESCROW");
        RescueEscrow escrow = RescueEscrow(escrowAddr);
        string memory op = vm.envOr("ESCROW_OP", string("inspect"));
        bytes32 escrowId = _resolveEscrowId(escrow);

        if (_eq(op, "inspect")) {
            _inspect(escrow, escrowId);
            return;
        }

        if (_eq(op, "claim")) {
            uint256 claimerPk = vm.envOr("CLAIMER_PRIVATE_KEY", vm.envUint("PRIVATE_KEY"));
            vm.startBroadcast(claimerPk);
            bool claimed = escrow.claimEscrow(escrowId);
            vm.stopBroadcast();
            console.log("Claim tx complete. claimed =", claimed);
            _inspect(escrow, escrowId);
            return;
        }

        if (_eq(op, "retry")) {
            uint256 operatorPk = vm.envOr("OPERATOR_PRIVATE_KEY", vm.envUint("PRIVATE_KEY"));
            bytes memory retryData = bytes(vm.envOr("RETRY_NOTE", string("manual-retry")));
            vm.startBroadcast(operatorPk);
            bool retried = escrow.retryTransfer(escrowId, retryData);
            vm.stopBroadcast();
            console.log("Retry tx complete. retried =", retried);
            _inspect(escrow, escrowId);
            return;
        }

        revert("EscrowOps: unsupported ESCROW_OP");
    }

    function _inspect(RescueEscrow escrow, bytes32 escrowId) internal view {
        ReprieveTypes.EscrowRecord memory record = escrow.getEscrow(escrowId);
        console.log("\n=== Escrow Record ===");
        console.log("escrowId:", vm.toString(record.escrowId));
        console.log("owner:", record.owner);
        console.log("asset:", record.asset);
        console.log("amount:", record.amount);
        console.log("sourceChain:", record.sourceChain);
        console.log("targetChain:", record.targetChain);
        console.log("status(enum):", uint256(record.status));
        console.log("createdAt:", record.createdAt);
        console.log("retryCount:", record.retryCount);
        console.log("relatedExecId:", vm.toString(record.relatedExecId));
    }

    function _resolveEscrowId(RescueEscrow escrow) internal view returns (bytes32) {
        string memory rawEscrowId = vm.envOr("ESCROW_ID", string(""));
        if (bytes(rawEscrowId).length > 0) {
            return vm.parseBytes32(rawEscrowId);
        }

        address user = vm.envOr("ESCROW_OWNER", address(0));
        require(user != address(0), "EscrowOps: set ESCROW_ID or ESCROW_OWNER");

        uint256 index = vm.envOr("ESCROW_INDEX", uint256(0));
        bytes32[] memory userEscrows = escrow.getUserEscrows(user);
        require(index < userEscrows.length, "EscrowOps: invalid ESCROW_INDEX");
        return userEscrows[index];
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
