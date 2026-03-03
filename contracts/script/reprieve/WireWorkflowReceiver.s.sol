// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {RescueExecutor} from "../../src/reprieve/RescueExecutor.sol";
import {ReprieveWorkflowReceiver} from "../../src/reprieve/ReprieveWorkflowReceiver.sol";

/**
 * @title WireWorkflowReceiver
 * @notice Wires workflow receiver + executor authorization and optional workflow identity guards.
 */
contract WireWorkflowReceiver is Script {
    function run() external {
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(ownerPrivateKey);

        address receiverAddr = vm.envAddress("WORKFLOW_RECEIVER");
        address rescueExecutorAddr = vm.envAddress("RESCUE_EXECUTOR");

        address forwarder = vm.envOr("CRE_FORWARDER", address(0));
        bool authorizeOnExecutor = vm.envOr("AUTHORIZE_WORKFLOW_RECEIVER", true);

        ReprieveWorkflowReceiver receiver = ReprieveWorkflowReceiver(receiverAddr);
        RescueExecutor executor = RescueExecutor(payable(rescueExecutorAddr));
        address expectedAuthor = vm.envOr("WF_EXPECTED_AUTHOR", receiver.getExpectedAuthor());

        console.log("Wiring workflow receiver as owner:", owner);
        console.log("Chain ID:", block.chainid);
        console.log("WorkflowReceiver:", receiverAddr);
        console.log("RescueExecutor:", rescueExecutorAddr);
        console.log("CRE Forwarder:", forwarder);
        console.log("Expected Author:", expectedAuthor);
        console.log("Workflow ID/Name validation: disabled (author-only mode)");
        console.log("Authorize on executor:", authorizeOnExecutor);

        vm.startBroadcast(ownerPrivateKey);

        if (authorizeOnExecutor) {
            executor.setAuthorizedWorkflow(receiverAddr, true);
        }
        if (forwarder != address(0)) {
            receiver.setForwarderAddress(forwarder);
        }
        receiver.setExpectedAuthor(expectedAuthor);
        // Keep receiver open to multiple workflows from the same author.
        receiver.setExpectedWorkflowId(bytes32(0));
        receiver.setExpectedWorkflowName("");

        vm.stopBroadcast();

        console.log("\n=== Workflow Receiver Wiring Verification ===");
        console.log("Executor auth:", executor.authorizedWorkflows(receiverAddr));
        console.log("Receiver forwarder:", receiver.getForwarderAddress());
        console.log("Receiver expected author:", receiver.getExpectedAuthor());
        console.log("Receiver expected workflow id:", vm.toString(receiver.getExpectedWorkflowId()));
    }
}
