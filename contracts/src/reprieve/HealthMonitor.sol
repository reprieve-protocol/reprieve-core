// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {ReprieveTypes} from "./libs/ReprieveTypes.sol";
import {ReprieveErrors} from "./libs/ReprieveErrors.sol";
import {ReprieveEvents} from "./libs/ReprieveEvents.sol";

/**
 * @title HealthMonitor
 * @notice Minimal on-chain checkpoint and alert surface for CRE risk snapshots
 * @dev Stores per-user health snapshots and emits urgent rescue signals.
 */
contract HealthMonitor is Ownable {
    /// @notice Addresses allowed to submit health snapshots and urgent alerts
    mapping(address => bool) public authorizedReporters;

    /// @notice User => snapshot history
    mapping(address => ReprieveTypes.HealthSnapshot[]) private snapshots;

    modifier onlyAuthorizedReporter() {
        if (!authorizedReporters[msg.sender]) revert ReprieveErrors.UnauthorizedWorkflow(msg.sender);
        _;
    }

    constructor(address initialOwner) Ownable(initialOwner) {}

    /**
     * @notice Authorize or revoke a reporter
     * @param reporter Reporter address
     * @param allowed True to authorize, false to revoke
     */
    function setAuthorizedReporter(address reporter, bool allowed) external onlyOwner {
        if (reporter == address(0)) revert ReprieveErrors.ZeroAddress();
        authorizedReporters[reporter] = allowed;
        emit ReprieveEvents.ReporterAuthorized(reporter, allowed);
    }

    /**
     * @notice Record a health snapshot for a user
     * @param user User address
     * @param aggregateHf Aggregate health factor (WAD)
     * @param timestamp Snapshot timestamp
     * @param execId Related execution ID
     */
    function recordHealthSnapshot(
        address user,
        uint256 aggregateHf,
        uint256 timestamp,
        bytes32 execId
    ) external onlyAuthorizedReporter {
        if (user == address(0)) revert ReprieveErrors.ZeroAddress();
        if (aggregateHf == 0) revert ReprieveErrors.ZeroAmount();

        uint256 ts = timestamp == 0 ? block.timestamp : timestamp;
        ReprieveTypes.HealthSnapshot memory snap = ReprieveTypes.HealthSnapshot({
            user: user,
            aggregateHf: aggregateHf,
            timestamp: ts,
            execId: execId
        });

        snapshots[user].push(snap);
        emit ReprieveEvents.HealthSnapshotRecorded(user, aggregateHf, ts, execId, msg.sender);
    }

    /**
     * @notice Emit an urgent rescue signal for sharp HF deterioration
     * @param user User address
     * @param prevHf Previous health factor (WAD)
     * @param newHf New health factor (WAD)
     */
    function emitUrgentRescue(
        address user,
        uint256 prevHf,
        uint256 newHf
    ) external onlyAuthorizedReporter {
        if (user == address(0)) revert ReprieveErrors.ZeroAddress();
        if (prevHf == 0 || newHf == 0) revert ReprieveErrors.ZeroAmount();
        if (newHf >= prevHf) revert ReprieveErrors.InvalidRescuePlan("newHf must be lower than prevHf");

        uint256 dropBps = ((prevHf - newHf) * 10_000) / prevHf;
        emit ReprieveEvents.UrgentRescue(user, prevHf, newHf, dropBps, msg.sender);
    }

    /**
     * @notice Get latest snapshot for user
     * @param user User address
     * @return Latest snapshot
     */
    function getLatestSnapshot(address user) external view returns (ReprieveTypes.HealthSnapshot memory) {
        ReprieveTypes.HealthSnapshot[] storage userSnaps = snapshots[user];
        if (userSnaps.length == 0) revert ReprieveErrors.InvalidRescuePlan("No snapshots");
        return userSnaps[userSnaps.length - 1];
    }

    /**
     * @notice Get snapshot count for user
     * @param user User address
     * @return Number of snapshots
     */
    function getSnapshotCount(address user) external view returns (uint256) {
        return snapshots[user].length;
    }

    /**
     * @notice Get snapshot by index
     * @param user User address
     * @param index Snapshot index
     * @return Snapshot at index
     */
    function getSnapshotAt(address user, uint256 index) external view returns (ReprieveTypes.HealthSnapshot memory) {
        ReprieveTypes.HealthSnapshot[] storage userSnaps = snapshots[user];
        if (index >= userSnaps.length) revert ReprieveErrors.InvalidStepIndex(index);
        return userSnaps[index];
    }
}
