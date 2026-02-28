// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReprieveTypes} from "../libs/ReprieveTypes.sol";

/**
 * @title IRescueLog
 * @notice Immutable on-chain audit trail for rescue attempts
 */
interface IRescueLog {
    event LogEntryAdded(bytes32 indexed execId, uint256 stepIndex, address indexed user, ReprieveTypes.RescueStatus status, string details);
    
    function logRescueInitiated(bytes32 execId, address user, uint256 steps) external;
    function logRescueStep(bytes32 execId, uint256 stepIndex, address user, string calldata details) external;
    function logRescueCompleted(bytes32 execId, address user, ReprieveTypes.RescueStatus status, string calldata details) external;
    function logRescueFailed(bytes32 execId, address user, string calldata reason) external;
    
    function getLogEntries(bytes32 execId) external view returns (ReprieveTypes.LogEntry[] memory);
}
