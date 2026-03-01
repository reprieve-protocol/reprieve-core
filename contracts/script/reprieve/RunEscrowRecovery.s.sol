// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {RescueEscrow} from "../../src/reprieve/RescueEscrow.sol";
import {ReprieveTypes} from "../../src/reprieve/libs/ReprieveTypes.sol";

/**
 * @title RunEscrowRecovery
 * @notice Executes escrow recovery flows from a pre-existing escrow record.
 * @dev Set RECOVERY_MODE=claim or RECOVERY_MODE=retry.
 */
contract RunEscrowRecovery is Script {
    function run() external {
        address escrowAddr = vm.envAddress("RESCUE_ESCROW");
        RescueEscrow escrow = RescueEscrow(escrowAddr);

        string memory mode = vm.envOr("RECOVERY_MODE", string("claim"));
        bytes32 escrowId = _resolveEscrowId(escrow);
        ReprieveTypes.EscrowRecord memory beforeRecord = escrow.getEscrow(escrowId);

        console.log("Running escrow recovery on chain:", block.chainid);
        console.log("Mode:", mode);
        console.log("EscrowId:", vm.toString(escrowId));
        console.log("Status before(enum):", uint256(beforeRecord.status));

        if (_eq(mode, "claim")) {
            uint256 userPk = vm.envOr("USER_PRIVATE_KEY", vm.envUint("PRIVATE_KEY"));
            vm.startBroadcast(userPk);
            bool claimed = escrow.claimEscrow(escrowId);
            vm.stopBroadcast();
            console.log("Claim tx result:", claimed);
        } else if (_eq(mode, "retry")) {
            uint256 operatorPk = vm.envOr("OPERATOR_PRIVATE_KEY", vm.envUint("PRIVATE_KEY"));
            bytes memory retryData = bytes(vm.envOr("RETRY_NOTE", string("retry-transfer")));
            vm.startBroadcast(operatorPk);
            bool retried = escrow.retryTransfer(escrowId, retryData);
            vm.stopBroadcast();
            console.log("Retry tx result:", retried);
        } else {
            revert("RunEscrowRecovery: RECOVERY_MODE must be claim or retry");
        }

        ReprieveTypes.EscrowRecord memory afterRecord = escrow.getEscrow(escrowId);
        console.log("Status after(enum):", uint256(afterRecord.status));
        console.log("Retry count after:", afterRecord.retryCount);
    }

    function _resolveEscrowId(RescueEscrow escrow) internal view returns (bytes32) {
        string memory rawEscrowId = vm.envOr("ESCROW_ID", string(""));
        if (bytes(rawEscrowId).length > 0) {
            return vm.parseBytes32(rawEscrowId);
        }

        address user = vm.envOr("ESCROW_OWNER", address(0));
        require(user != address(0), "RunEscrowRecovery: set ESCROW_ID or ESCROW_OWNER");

        uint256 index = vm.envOr("ESCROW_INDEX", uint256(0));
        bytes32[] memory userEscrows = escrow.getUserEscrows(user);
        require(index < userEscrows.length, "RunEscrowRecovery: invalid ESCROW_INDEX");
        return userEscrows[index];
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
