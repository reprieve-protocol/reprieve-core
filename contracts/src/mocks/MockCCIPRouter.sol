// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ICCIPRouter} from "../reprieve/libs/CCIPClient.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {CCIPClient} from "../reprieve/libs/CCIPClient.sol";

/**
 * @title MockCCIPRouter
 * @notice Simulates Chainlink CCIP router for testing
 * @dev Both source and destination contracts are on the same chain for testing
 */
contract MockCCIPRouter is ICCIPRouter {
    
    struct StoredMessage {
        uint64 destinationChainSelector;
        address sender;
        bytes receiver;  // abi-encoded receiver address
        bytes data;
        CCIPClient.EVMTokenAmount[] tokenAmounts;
        bytes extraArgs;
        address feeToken;
        uint256 timestamp;
    }
    
    /// @notice Message ID => stored message
    mapping(bytes32 => StoredMessage) public messages;
    
    /// @notice Chain selector => mock fee
    mapping(uint64 => uint256) public mockFees;
    
    /// @notice Counter for unique message IDs
    uint256 public messageCounter;
    
    /// @notice LINK token address for fee payment
    address public linkToken;
    
    /// @notice Event when message is "sent"
    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address sender,
        address receiver
    );
    
    /// @notice Event when message is "delivered"
    event MessageDelivered(
        bytes32 indexed messageId,
        address receiver,
        uint256 tokenCount
    );
    
    constructor(address _linkToken) {
        linkToken = _linkToken;
        // Set default mock fees for common test chains
        mockFees[10344971235874465080] = 0.01 ether; // Base Sepolia
        mockFees[16015286601757825753] = 0.015 ether; // Arbitrum Sepolia
    }
    
    /**
     * @notice Set mock fee for a chain
     */
    function setMockFee(uint64 chainSelector, uint256 fee) external {
        mockFees[chainSelector] = fee;
    }
    
    /**
     * @notice Get fee for a message (CCIP interface)
     */
    function getFee(
        uint64 destinationChainSelector,
        CCIPClient.EVM2AnyMessage calldata message
    ) external view override returns (uint256 fee) {
        // Check fee token is valid
        if (message.feeToken != linkToken) {
            // If not paying in LINK, return ETH fee
            return mockFees[destinationChainSelector];
        }
        return mockFees[destinationChainSelector];
    }
    
    /**
     * @notice Send message via CCIP (stores it for later delivery)
     */
    function ccipSend(
        uint64 destinationChainSelector,
        CCIPClient.EVM2AnyMessage calldata message
    ) external payable override returns (bytes32 messageId) {
        messageCounter++;
        messageId = keccak256(abi.encodePacked(
            messageCounter,
            msg.sender,
            destinationChainSelector,
            block.timestamp
        ));
        
        // Store token amounts
        CCIPClient.EVMTokenAmount[] memory tokens = new CCIPClient.EVMTokenAmount[](message.tokenAmounts.length);
        for (uint i = 0; i < message.tokenAmounts.length; i++) {
            tokens[i] = CCIPClient.EVMTokenAmount({
                token: message.tokenAmounts[i].token,
                amount: message.tokenAmounts[i].amount
            });
            
            // Pull tokens from sender (simulating bridge lock)
            IERC20(tokens[i].token).transferFrom(msg.sender, address(this), tokens[i].amount);
        }
        
        // If paying with LINK, pull fee
        if (message.feeToken == linkToken) {
            uint256 fee = mockFees[destinationChainSelector];
            IERC20(linkToken).transferFrom(msg.sender, address(this), fee);
        } else {
            // ETH payment
            require(msg.value >= mockFees[destinationChainSelector], "Insufficient fee");
        }
        
        messages[messageId] = StoredMessage({
            destinationChainSelector: destinationChainSelector,
            sender: msg.sender,
            receiver: message.receiver,
            data: message.data,
            tokenAmounts: tokens,
            extraArgs: message.extraArgs,
            feeToken: message.feeToken,
            timestamp: block.timestamp
        });
        
        emit MessageSent(messageId, destinationChainSelector, msg.sender, _decodeReceiver(message.receiver));
        
        return messageId;
    }
    
    /**
     * @notice Deliver a stored message to the receiver (test helper)
     * @dev This simulates CCIP delivering the message on the destination chain
     */
    function deliverMessage(bytes32 messageId) external {
        StoredMessage storage stored = messages[messageId];
        require(stored.timestamp > 0, "Message not found");
        
        address receiver = _decodeReceiver(stored.receiver);
        
        // Build Any2EVMMessage
        CCIPClient.Any2EVMMessage memory message = CCIPClient.Any2EVMMessage({
            messageId: messageId,
            sourceChainSelector: _getSourceChainSelector(stored.destinationChainSelector),
            sender: abi.encode(stored.sender),
            data: stored.data,
            destTokenAmounts: stored.tokenAmounts
        });
        
        // Transfer tokens to receiver (simulating CCIP bridge mint/unlock)
        for (uint i = 0; i < stored.tokenAmounts.length; i++) {
            IERC20(stored.tokenAmounts[i].token).transfer(receiver, stored.tokenAmounts[i].amount);
        }
        
        // Call receiver (simulates ccipReceive)
        (bool success, ) = receiver.call(
            abi.encodeWithSignature("ccipReceive((bytes32,uint64,bytes,bytes,(address,uint256)[]))", message)
        );
        require(success, "Delivery failed");
        
        emit MessageDelivered(messageId, receiver, stored.tokenAmounts.length);
        
        // Clear stored message
        delete messages[messageId];
    }
    
    /**
     * @notice Deliver with specific source chain (for testing different scenarios)
     */
    function deliverMessageWithSource(bytes32 messageId, uint64 sourceChainSelector) external {
        StoredMessage storage stored = messages[messageId];
        require(stored.timestamp > 0, "Message not found");
        
        address receiver = _decodeReceiver(stored.receiver);
        
        CCIPClient.Any2EVMMessage memory message = CCIPClient.Any2EVMMessage({
            messageId: messageId,
            sourceChainSelector: sourceChainSelector,
            sender: abi.encode(stored.sender),
            data: stored.data,
            destTokenAmounts: stored.tokenAmounts
        });
        
        // Transfer tokens
        for (uint i = 0; i < stored.tokenAmounts.length; i++) {
            IERC20(stored.tokenAmounts[i].token).transfer(receiver, stored.tokenAmounts[i].amount);
        }
        
        // Call receiver
        (bool success, ) = receiver.call(
            abi.encodeWithSignature("ccipReceive((bytes32,uint64,bytes,bytes,(address,uint256)[]))", message)
        );
        require(success, "Delivery failed");
        
        delete messages[messageId];
    }
    
    /**
     * @notice Get stored message details
     */
    function getMessage(bytes32 messageId) external view returns (StoredMessage memory) {
        return messages[messageId];
    }
    
    /**
     * @notice Helper to decode receiver address from bytes
     */
    function _decodeReceiver(bytes memory receiver) internal pure returns (address) {
        if (receiver.length == 32) {
            // abi-encoded address
            return abi.decode(receiver, (address));
        } else if (receiver.length == 20) {
            // raw address
            return address(uint160(bytes20(receiver)));
        }
        revert("Invalid receiver format");
    }
    
    /**
     * @notice Get source chain selector based on destination (for testing)
     * @dev In real CCIP, source and dest are different chains
     */
    function _getSourceChainSelector(uint64 destChain) internal pure returns (uint64) {
        // Simple mapping for test chains
        if (destChain == 10344971235874465080) return 16015286601757825753; // Base -> Arbitrum
        if (destChain == 16015286601757825753) return 10344971235874465080; // Arbitrum -> Base
        return 12345; // default
    }
}
