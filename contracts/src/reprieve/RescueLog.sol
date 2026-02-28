// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {IRescueLog} from "./interfaces/IRescueLog.sol";
import {ReprieveTypes} from "./libs/ReprieveTypes.sol";
import {ReprieveErrors} from "./libs/ReprieveErrors.sol";
import {ReprieveEvents} from "./libs/ReprieveEvents.sol";

/**
 * @title RescueLog
 * @notice Immutable on-chain audit trail for rescue attempts
 * @dev Append-only log with authorized writer contracts
 */
contract RescueLog is IRescueLog, Ownable {
    
    /// @notice Authorized writer contracts (executor, receiver, escrow)
    mapping(address => bool) public authorizedWriters;
    
    /// @notice execId => Log entries
    mapping(bytes32 => ReprieveTypes.LogEntry[]) private logEntries;
    
    /// @notice execId => exists flag
    mapping(bytes32 => bool) public hasEntries;
    
    /// @notice Total log entries across all executions
    uint256 public totalEntries;
    
    modifier onlyAuthorizedWriter() {
        if (!authorizedWriters[msg.sender]) revert ReprieveErrors.UnauthorizedWorkflow(msg.sender);
        _;
    }
    
    constructor(address initialOwner) Ownable(initialOwner) {}
    
    /**
     * @notice Authorize a contract to write logs
     * @param writer Address to authorize
     * @param allowed True to authorize, false to revoke
     */
    function setAuthorizedWriter(address writer, bool allowed) external onlyOwner {
        if (writer == address(0)) revert ReprieveErrors.ZeroAddress();
        authorizedWriters[writer] = allowed;
        emit ReprieveEvents.WriterAuthorized(writer, allowed);
    }
    
    /**
     * @notice Log the start of a rescue operation
     * @param execId Unique execution ID
     * @param user User being rescued
     * @param steps Number of steps in the rescue plan
     */
    function logRescueInitiated(bytes32 execId, address user, uint256 steps) 
        external 
        override 
        onlyAuthorizedWriter 
    {
        if (hasEntries[execId]) revert ReprieveErrors.RescueAlreadyInProgress(user);
        
        string memory details = string.concat(
            "Initiated with ",
            _uintToString(steps),
            " steps"
        );
        
        ReprieveTypes.LogEntry memory entry = ReprieveTypes.LogEntry({
            execId: execId,
            stepIndex: 0,
            user: user,
            status: ReprieveTypes.RescueStatus.InProgress,
            timestamp: block.timestamp,
            details: details
        });
        
        logEntries[execId].push(entry);
        hasEntries[execId] = true;
        totalEntries++;
        
        emit ReprieveEvents.LogEntryAdded(execId, 0, user, ReprieveTypes.RescueStatus.InProgress, details);
        emit ReprieveEvents.RescueInitiated(execId, user, steps, block.timestamp + 1 hours);
    }
    
    /**
     * @notice Log a rescue step execution
     * @param execId Unique execution ID
     * @param stepIndex Index of the step
     * @param user User being rescued
     * @param details Description of the step
     */
    function logRescueStep(bytes32 execId, uint256 stepIndex, address user, string calldata details) 
        external 
        override 
        onlyAuthorizedWriter 
    {
        if (!hasEntries[execId]) revert ReprieveErrors.InvalidRescuePlan("ExecId not found");
        
        ReprieveTypes.LogEntry memory entry = ReprieveTypes.LogEntry({
            execId: execId,
            stepIndex: stepIndex,
            user: user,
            status: ReprieveTypes.RescueStatus.InProgress,
            timestamp: block.timestamp,
            details: details
        });
        
        logEntries[execId].push(entry);
        totalEntries++;
        
        emit ReprieveEvents.LogEntryAdded(execId, stepIndex, user, ReprieveTypes.RescueStatus.InProgress, details);
    }
    
    /**
     * @notice Log rescue completion
     * @param execId Unique execution ID
     * @param user User being rescued
     * @param status Final status (Completed, Partial, Failed)
     * @param details Completion details
     */
    function logRescueCompleted(bytes32 execId, address user, ReprieveTypes.RescueStatus status, string calldata details) 
        external 
        override 
        onlyAuthorizedWriter 
    {
        if (!hasEntries[execId]) revert ReprieveErrors.InvalidRescuePlan("ExecId not found");
        
        ReprieveTypes.LogEntry memory entry = ReprieveTypes.LogEntry({
            execId: execId,
            stepIndex: _getLastStepIndex(execId) + 1,
            user: user,
            status: status,
            timestamp: block.timestamp,
            details: details
        });
        
        logEntries[execId].push(entry);
        totalEntries++;
        
        emit ReprieveEvents.LogEntryAdded(execId, entry.stepIndex, user, status, details);
        emit ReprieveEvents.RescueCompleted(execId, user, status, entry.stepIndex);
    }
    
    /**
     * @notice Log rescue failure
     * @param execId Unique execution ID
     * @param user User being rescued
     * @param reason Failure reason
     */
    function logRescueFailed(bytes32 execId, address user, string calldata reason) 
        external 
        override 
        onlyAuthorizedWriter 
    {
        if (!hasEntries[execId]) revert ReprieveErrors.InvalidRescuePlan("ExecId not found");
        
        ReprieveTypes.LogEntry memory entry = ReprieveTypes.LogEntry({
            execId: execId,
            stepIndex: _getLastStepIndex(execId) + 1,
            user: user,
            status: ReprieveTypes.RescueStatus.Failed,
            timestamp: block.timestamp,
            details: reason
        });
        
        logEntries[execId].push(entry);
        totalEntries++;
        
        emit ReprieveEvents.LogEntryAdded(execId, entry.stepIndex, user, ReprieveTypes.RescueStatus.Failed, reason);
        emit ReprieveEvents.RescueFailed(execId, user, reason, entry.stepIndex);
    }
    
    /**
     * @notice Get all log entries for an execution
     * @param execId Unique execution ID
     * @return Array of log entries
     */
    function getLogEntries(bytes32 execId) 
        external 
        view 
        override 
        returns (ReprieveTypes.LogEntry[] memory) 
    {
        return logEntries[execId];
    }
    
    /**
     * @notice Get log entry count for an execution
     * @param execId Unique execution ID
     * @return Number of entries
     */
    function getLogEntryCount(bytes32 execId) external view returns (uint256) {
        return logEntries[execId].length;
    }
    
    /**
     * @notice Get a specific log entry
     * @param execId Unique execution ID
     * @param index Entry index
     * @return Log entry
     */
    function getLogEntry(bytes32 execId, uint256 index) 
        external 
        view 
        returns (ReprieveTypes.LogEntry memory) 
    {
        require(index < logEntries[execId].length, "Index out of bounds");
        return logEntries[execId][index];
    }
    
    /**
     * @notice Check if address is authorized writer
     * @param writer Address to check
     * @return True if authorized
     */
    function isAuthorizedWriter(address writer) external view returns (bool) {
        return authorizedWriters[writer];
    }
    
    // ============ Internal Helpers ============
    
    function _getLastStepIndex(bytes32 execId) internal view returns (uint256) {
        ReprieveTypes.LogEntry[] storage entries = logEntries[execId];
        if (entries.length == 0) return 0;
        return entries[entries.length - 1].stepIndex;
    }
    
    function _uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }
        
        return string(buffer);
    }
}
