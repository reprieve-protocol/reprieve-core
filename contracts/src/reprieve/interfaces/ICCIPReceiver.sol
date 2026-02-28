// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ICCIPReceiver
 * @notice Interface for CCIP receiver handling rescue payloads
 * @dev Minimal version for Slide 1 - will integrate Chainlink CCIP library in Slide 6
 */
interface ICCIPReceiver {
    // Minimal Any2EVMMessage struct for interface definition
    struct Any2EVMMessage {
        bytes32 messageId;
        uint64 sourceChainSelector;
        bytes sender;
        bytes data;
        // Token transfers would be added here in full implementation
    }
    
    event MessageReceived(bytes32 indexed messageId, uint64 indexed sourceChainSelector, address sender);
    event ExecutorSet(address executor);
    event RouterSet(address router);
    event SourceChainAllowed(uint64 chainSelector, bool allowed);
    event SenderAllowed(uint64 chainSelector, address sender, bool allowed);
    
    function ccipReceive(Any2EVMMessage calldata message) external;
    function setExecutor(address executor) external;
    function setRouter(address router) external;
    function setAllowedSourceChain(uint64 chainSelector, bool allowed) external;
    function setAllowedSender(uint64 chainSelector, address sender, bool allowed) external;
    
    function getExecutor() external view returns (address);
    function getRouter() external view returns (address);
    function isAllowedSourceChain(uint64 chainSelector) external view returns (bool);
    function isAllowedSender(uint64 chainSelector, address sender) external view returns (bool);
}
