// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {RescueExecutor} from "../../src/reprieve/RescueExecutor.sol";
import {ReprieveWorkflowReceiver} from "../../src/reprieve/ReprieveWorkflowReceiver.sol";

/**
 * @title DeployWorkflowReceiver
 * @notice Deploys ReprieveWorkflowReceiver and optionally authorizes it on RescueExecutor.
 */
contract DeployWorkflowReceiver is Script {
    function run() external {
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(ownerPrivateKey);

        address rescueExecutorAddr = vm.envAddress("RESCUE_EXECUTOR");
        address forwarder = vm.envAddress("CRE_FORWARDER");
        bool authorizeOnExecutor = vm.envOr("AUTHORIZE_WORKFLOW_RECEIVER", true);

        console.log("Deploying ReprieveWorkflowReceiver as owner:", owner);
        console.log("Chain ID:", block.chainid);
        console.log("RescueExecutor:", rescueExecutorAddr);
        console.log("CRE Forwarder:", forwarder);
        console.log("Authorize on executor:", authorizeOnExecutor);

        vm.startBroadcast(ownerPrivateKey);

        ReprieveWorkflowReceiver receiver =
            new ReprieveWorkflowReceiver(owner, forwarder, rescueExecutorAddr);

        if (authorizeOnExecutor) {
            RescueExecutor(payable(rescueExecutorAddr)).setAuthorizedWorkflow(address(receiver), true);
        }

        vm.stopBroadcast();

        _writeArtifact(address(receiver), rescueExecutorAddr, forwarder, authorizeOnExecutor);

        console.log("\n=== Workflow Receiver Deployment ===");
        console.log("WorkflowReceiver:", address(receiver));
        console.log(
            "Executor auth:",
            RescueExecutor(payable(rescueExecutorAddr)).authorizedWorkflows(address(receiver))
        );
    }

    function _writeArtifact(
        address workflowReceiver,
        address rescueExecutor,
        address forwarder,
        bool executorAuthorized
    ) internal {
        string memory path = string.concat("config/reprieve-workflow-receiver-", vm.toString(block.chainid), ".json");
        string memory out = string.concat(
            '{"chainId":',
            vm.toString(block.chainid),
            ',"contracts":{"WorkflowReceiver":"',
            vm.toString(workflowReceiver),
            '","RescueExecutor":"',
            vm.toString(rescueExecutor),
            '"},"wiring":{"forwarder":"',
            vm.toString(forwarder),
            '","authorizedOnExecutor":',
            executorAuthorized ? "true" : "false",
            "}}"
        );
        vm.writeFile(path, out);
        console.log("Artifact written:", path);
    }
}
