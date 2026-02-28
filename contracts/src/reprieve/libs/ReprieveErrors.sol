// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ReprieveErrors
 * @notice Centralized custom errors for gas-efficient revert reasons
 */
library ReprieveErrors {
    // Authorization
    error UnauthorizedWorkflow(address caller);
    error NotRescueExecutor();
    error NotRescueEscrow();
    error NotRescueLog();
    error NotCCIPReceiver();
    error NotAdapterRegistry();
    error NotOwner();
    
    // Rescue state
    error RescueAlreadyInProgress(address user);
    error RescueNotInProgress(address user);
    error RescueExpired(bytes32 execId);
    error InvalidRescuePlan(string reason);
    error InvalidStepIndex(uint256 stepIndex);
    
    // Budget and fees
    error BudgetExceeded(uint256 cost, uint256 budget);
    error InsufficientFeePayment(uint256 required, uint256 provided);
    error FeeQuoteFailed();
    
    // Adapter
    error InvalidAdapter(bytes32 protocolId);
    error AdapterNotRegistered(address adapter);
    error UnsupportedProtocol(bytes32 protocolId);
    error UnsupportedAsset(address asset);
    
    // Escrow
    error EscrowNotClaimable(bytes32 escrowId);
    error EscrowAlreadyClaimed(bytes32 escrowId);
    error EscrowNotRetriable(bytes32 escrowId);
    error EscrowExpired(bytes32 escrowId);
    error InvalidEscrowId(bytes32 escrowId);
    
    // CCIP
    error CCIPRouterNotSet();
    error CCIPDestinationNotAllowed(uint64 chainSelector);
    error CCIPSourceNotAllowed(uint64 chainSelector);
    error CCIPSenderNotAllowed(address sender);
    error CCIPMessageInvalid();
    error CCIPTransferFailed(bytes32 messageId);
    
    // Execution
    error WithdrawFailed(address adapter);
    error RepayFailed(address adapter);
    error SameChainTransferFailed();
    error CrossChainTransferFailed();
    
    // General
    error ZeroAddress();
    error ZeroAmount();
    error DeadlinePassed(uint256 deadline, uint256 currentTime);
    error ArrayLengthMismatch();
}
