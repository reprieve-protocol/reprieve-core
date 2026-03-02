// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ReprieveTypes
 * @notice Shared structs and enums used across Reprieve protocol contracts
 */
library ReprieveTypes {
    /// @notice Rescue action mode for an execution plan
    enum RescueMode {
        TOP_UP,         // Increase target collateral
        REPAY           // Reduce target debt
    }

    /// @notice Status of a rescue operation
    enum RescueStatus {
        None,           // No rescue in progress
        InProgress,     // Rescue is being executed
        Completed,      // Rescue completed successfully
        Partial,        // Partial success (improved but not fully recovered)
        Failed,         // Rescue failed, funds in escrow
        Cancelled       // Rescue cancelled by governance/emergency
    }

    /// @notice Status of an escrow record
    enum EscrowStatus {
        None,
        Pending,        // Funds held in escrow
        Claimed,        // User claimed funds
        Retried,        // Retry attempted
        Expired         // Escrow expired without claim
    }

    /// @notice A single step in a rescue plan
    struct RescueStep {
        uint256 stepIndex;          // Step order index
        address sourceAdapter;      // Adapter to withdraw from
        address targetAdapter;      // Adapter to repay to
        address collateralAsset;    // Asset to withdraw
        address debtAsset;          // Asset to repay
        uint256 collateralAmount;   // Amount to withdraw
        uint256 debtAmount;         // Amount to repay
        bool isCrossChain;          // Whether this step involves CCIP
        uint64 targetChain;         // Target chain selector (if cross-chain)
    }

    /// @notice Complete rescue plan for a user
    struct RescuePlan {
        bytes32 execId;             // Unique execution ID
        address user;               // User to rescue
        RescueMode mode;            // Execution mode for all steps
        RescueStep[] steps;         // Ordered rescue steps
        uint256 deadline;           // Execution deadline timestamp
        uint256 maxFee;             // Maximum acceptable fee
    }

    /// @notice Record of an escrowed rescue
    struct EscrowRecord {
        bytes32 escrowId;           // Unique escrow ID
        address owner;              // Original user
        address asset;              // Asset held
        uint256 amount;             // Amount held
        uint256 sourceChain;        // Source chain ID
        uint256 targetChain;        // Target chain ID
        EscrowStatus status;        // Current status
        uint256 createdAt;          // Creation timestamp
        uint256 retryCount;         // Number of retry attempts
        bytes32 relatedExecId;      // Related rescue execution ID
    }

    /// @notice Cross-chain rescue message payload
    struct CCIPMessage {
        bytes32 execId;             // Execution ID
        address user;               // User to rescue
        RescueMode mode;            // Execution mode
        address targetAdapter;      // Target adapter address
        address asset;              // Asset being transferred
        uint256 amount;             // Amount
        uint256 timestamp;          // Message timestamp
        uint256 deadline;           // Execution deadline
    }

    /// @notice Log entry for rescue actions
    struct LogEntry {
        bytes32 execId;             // Execution ID
        uint256 stepIndex;          // Step index
        address user;               // User
        RescueStatus status;        // Status
        uint256 timestamp;          // Timestamp
        string details;             // Additional details
    }

    /// @notice Health snapshot for a user
    struct HealthSnapshot {
        address user;               // User address
        uint256 aggregateHf;        // Aggregate health factor
        uint256 timestamp;          // Snapshot timestamp
        bytes32 execId;             // Related execution ID
    }
}
