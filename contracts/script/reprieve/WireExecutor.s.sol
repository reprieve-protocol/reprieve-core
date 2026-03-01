// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {RescueExecutor} from "../../src/reprieve/RescueExecutor.sol";
import {RescueLog} from "../../src/reprieve/RescueLog.sol";
import {RescueEscrow} from "../../src/reprieve/RescueEscrow.sol";
import {HealthMonitor} from "../../src/reprieve/HealthMonitor.sol";

/**
 * @title WireExecutor
 * @notice Wires core executor-related permissions and optional workflow/reporter roles.
 * @dev Intended to run after deploying executor/log/escrow/receiver.
 */
contract WireExecutor is Script {
    function run() external {
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(ownerPrivateKey);

        address executorAddr = vm.envAddress("RESCUE_EXECUTOR");
        address rescueLogAddr = vm.envAddress("RESCUE_LOG");
        address rescueEscrowAddr = vm.envAddress("RESCUE_ESCROW");
        address receiverAddr = vm.envOr("CCIP_RECEIVER", address(0));
        address workflow = vm.envOr("WORKFLOW", address(0));
        bool workflowAllowed = vm.envOr("WORKFLOW_ALLOWED", true);
        address healthMonitorAddr = vm.envOr("HEALTH_MONITOR", address(0));
        address reporter = vm.envOr("REPORTER", workflow);

        RescueExecutor executor = RescueExecutor(payable(executorAddr));
        RescueLog rescueLog = RescueLog(rescueLogAddr);
        RescueEscrow rescueEscrow = RescueEscrow(rescueEscrowAddr);

        console.log("Wiring executor permissions as owner:", owner);
        console.log("Executor:", executorAddr);
        console.log("RescueLog:", rescueLogAddr);
        console.log("RescueEscrow:", rescueEscrowAddr);
        console.log("CCIPReceiver (optional):", receiverAddr);
        console.log("Workflow (optional):", workflow);
        console.log("HealthMonitor (optional):", healthMonitorAddr);
        console.log("Reporter (optional):", reporter);

        vm.startBroadcast(ownerPrivateKey);

        rescueLog.setAuthorizedWriter(executorAddr, true);
        rescueEscrow.setAuthorizedDepositor(executorAddr, true);

        if (receiverAddr != address(0)) {
            rescueLog.setAuthorizedWriter(receiverAddr, true);
            rescueEscrow.setAuthorizedDepositor(receiverAddr, true);
        }

        if (workflow != address(0)) {
            executor.setAuthorizedWorkflow(workflow, workflowAllowed);
        }

        if (healthMonitorAddr != address(0) && reporter != address(0)) {
            HealthMonitor(healthMonitorAddr).setAuthorizedReporter(reporter, true);
        }

        vm.stopBroadcast();

        console.log("\n=== Wiring Verification ===");
        console.log("Executor writer auth:", rescueLog.isAuthorizedWriter(executorAddr));
        console.log("Executor depositor auth:", rescueEscrow.authorizedDepositors(executorAddr));
        if (receiverAddr != address(0)) {
            console.log("Receiver writer auth:", rescueLog.isAuthorizedWriter(receiverAddr));
            console.log("Receiver depositor auth:", rescueEscrow.authorizedDepositors(receiverAddr));
        }
        if (workflow != address(0)) {
            console.log("Workflow auth:", executor.authorizedWorkflows(workflow));
        }
        if (healthMonitorAddr != address(0) && reporter != address(0)) {
            console.log("Reporter auth:", HealthMonitor(healthMonitorAddr).authorizedReporters(reporter));
        }
    }
}
