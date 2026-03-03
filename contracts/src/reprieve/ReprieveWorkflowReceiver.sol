// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRescueExecutor} from "./interfaces/IRescueExecutor.sol";
import {WorkflowReceiverTemplate} from "./interfaces/WorkflowReceiverTemplate.sol";
import {ReprieveTypes} from "./libs/ReprieveTypes.sol";

/**
 * @title ReprieveWorkflowReceiver
 * @notice CRE-compatible report receiver that executes RescueExecutor plans.
 * @dev Report payload must be ABI-encoded `ReprieveTypes.RescuePlan`.
 */
contract ReprieveWorkflowReceiver is WorkflowReceiverTemplate {
    IRescueExecutor public immutable rescueExecutor;

    /// @notice Tracks successfully processed execution IDs to prevent replay.
    mapping(bytes32 => bool) public processedExecIds;

    error InvalidExecutorAddress();
    error EmptyReport();
    error InvalidReportPlan();
    error DuplicateExecution(bytes32 execId);
    error RescueExecutionFailed(bytes32 execId);

    event RescueReportProcessed(bytes32 indexed execId, address indexed user, bool success);

    constructor(address initialOwner, address forwarderAddress, address executorAddress)
        WorkflowReceiverTemplate(initialOwner, forwarderAddress)
    {
        if (executorAddress == address(0)) revert InvalidExecutorAddress();
        rescueExecutor = IRescueExecutor(executorAddress);
    }

    function _processReport(bytes calldata report) internal override {
        if (report.length == 0) revert EmptyReport();

        ReprieveTypes.RescuePlan memory plan = abi.decode(report, (ReprieveTypes.RescuePlan));
        if (plan.execId == bytes32(0) || plan.user == address(0) || plan.steps.length == 0) {
            revert InvalidReportPlan();
        }

        if (processedExecIds[plan.execId]) revert DuplicateExecution(plan.execId);

        bool success = rescueExecutor.executeRescue(plan);
        if (!success) revert RescueExecutionFailed(plan.execId);

        processedExecIds[plan.execId] = true;
        emit RescueReportProcessed(plan.execId, plan.user, true);
    }
}
