// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReprieveTypes} from "../libs/ReprieveTypes.sol";

/**
 * @title IRescueExecutor
 * @notice Interface for the main rescue execution contract
 */
interface IRescueExecutor {
    // Events
    event RescueInitiated(bytes32 indexed execId, address indexed user, uint256 steps);
    event RescueStepCompleted(bytes32 indexed execId, uint256 stepIndex, address sourceAdapter, address targetAdapter, uint256 amount);
    event RescueCompleted(bytes32 indexed execId, address indexed user, ReprieveTypes.RescueStatus status);
    event RescueFailed(bytes32 indexed execId, address indexed user, string reason);
    event CrossChainInitiated(bytes32 indexed execId, uint64 targetChain, bytes32 ccipMessageId);
    event CrossChainCompleted(bytes32 indexed execId, bytes32 ccipMessageId);
    
    // Core functions
    function executeRescue(ReprieveTypes.RescuePlan calldata plan) external returns (bool success);
    function executeSameChainLeg(ReprieveTypes.RescueStep calldata step, address user, bytes32 execId) external returns (bool);
    function completeCrossChainLeg(bytes32 execId, address user, address targetAdapter, address asset, uint256 amount) external returns (bool);
    
    // State checks
    function rescueInProgress(address user) external view returns (bool);
    function getRescueStatus(bytes32 execId) external view returns (ReprieveTypes.RescueStatus);
    
    // Authorization
    function authorizedWorkflows(address workflow) external view returns (bool);
    function setAuthorizedWorkflow(address workflow, bool allowed) external;
    
    // CCIP config
    function quoteCcipFee(uint64 targetChain, bytes memory message) external view returns (uint256 fee);
    function setCcipExtraArgs(uint64 targetChain, bytes calldata extraArgs) external;
}
