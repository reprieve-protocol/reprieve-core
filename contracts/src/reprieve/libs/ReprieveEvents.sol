// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReprieveTypes} from "./ReprieveTypes.sol";

/**
 * @title ReprieveEvents
 * @notice Common event definitions for consistent event schema across contracts
 */
library ReprieveEvents {
    // Rescue lifecycle events
    event RescueInitiated(
        bytes32 indexed execId,
        address indexed user,
        uint256 steps,
        uint256 deadline
    );
    
    event RescueStepStarted(
        bytes32 indexed execId,
        uint256 indexed stepIndex,
        address sourceAdapter,
        address targetAdapter
    );
    
    event RescueStepCompleted(
        bytes32 indexed execId,
        uint256 indexed stepIndex,
        address sourceAdapter,
        address targetAdapter,
        uint256 collateralAmount,
        uint256 debtAmount
    );
    
    event RescueCompleted(
        bytes32 indexed execId,
        address indexed user,
        ReprieveTypes.RescueStatus status,
        uint256 finalStepIndex
    );
    
    event RescueFailed(
        bytes32 indexed execId,
        address indexed user,
        string reason,
        uint256 failedStepIndex
    );
    
    // Cross-chain events
    event CrossChainInitiated(
        bytes32 indexed execId,
        uint64 indexed targetChain,
        bytes32 indexed ccipMessageId,
        uint256 feePaid
    );
    
    event CrossChainCompleted(
        bytes32 indexed execId,
        bytes32 indexed ccipMessageId,
        uint256 amountReceived
    );
    
    event CrossChainSourceFailed(
        bytes32 indexed execId,
        string reason,
        uint256 failedAtStep
    );
    
    event CrossChainDestinationFailed(
        bytes32 indexed execId,
        bytes32 indexed ccipMessageId,
        string reason
    );
    
    // Escrow events
    event EscrowCreated(
        bytes32 indexed escrowId,
        address indexed owner,
        address asset,
        uint256 amount,
        bytes32 relatedExecId
    );
    
    event EscrowClaimed(
        bytes32 indexed escrowId,
        address indexed claimer,
        uint256 amount
    );
    
    event EscrowRetried(
        bytes32 indexed escrowId,
        uint256 retryCount,
        bytes32 newExecId
    );
    
    // Log events
    event LogEntryAdded(
        bytes32 indexed execId,
        uint256 indexed stepIndex,
        address indexed user,
        ReprieveTypes.RescueStatus status,
        string details
    );
    
    // Authorization events
    event WorkflowAuthorized(address indexed workflow, bool allowed);
    event WriterAuthorized(address indexed writer, bool allowed);
    event ReporterAuthorized(address indexed reporter, bool allowed);
    event OperatorSet(address indexed operator);
    event ExecutorSet(address executor);
    event RouterSet(address router);

    // Health monitoring events
    event HealthSnapshotRecorded(
        address indexed user,
        uint256 aggregateHf,
        uint256 timestamp,
        bytes32 indexed execId,
        address indexed reporter
    );
    
    event UrgentRescue(
        address indexed user,
        uint256 prevHf,
        uint256 newHf,
        uint256 dropBps,
        address indexed reporter
    );
    
    // CCIP config events
    event CcipExtraArgsSet(uint64 indexed chainSelector, bytes extraArgs);
    event CcipRouterSet(address router);
    event CcipDestinationAllowed(uint64 chainSelector, bool allowed);
    event SourceChainAllowed(uint64 chainSelector, bool allowed);
    event SenderAllowed(uint64 chainSelector, address sender, bool allowed);
}
