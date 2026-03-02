// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ICCIPRouter} from "../reprieve/libs/CCIPClient.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {CCIPClient} from "../reprieve/libs/CCIPClient.sol";

interface IMockBridgeToken {
    function bridgeBurn(address from, uint256 amount) external;
    function bridgeMint(address to, uint256 amount) external;
}

/**
 * @title MockCCIPRouter
 * @notice Simulates Chainlink CCIP router for testing
 * @dev Both source and destination contracts are on the same chain for testing
 */
contract MockCCIPRouter is ICCIPRouter {
    enum MessageStatus {
        None,
        Pending,
        Delivered,
        Failed
    }

    struct StoredMessage {
        uint64 sourceChainSelector;
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

    /// @notice Message ID => lifecycle status
    mapping(bytes32 => MessageStatus) public messageStatus;

    /// @notice Message ID => last failure reason
    mapping(bytes32 => string) public messageFailureReason;
    
    /// @notice Chain selector => mock fee
    mapping(uint64 => uint256) public mockFees;

    /// @notice Source chain => destination chain => enabled lane
    mapping(uint64 => mapping(uint64 => bool)) public lanes;

    /// @notice Destination chain => source token => destination token
    mapping(uint64 => mapping(address => address)) public tokenMappings;

    /// @notice Destination chain => expected receiver
    mapping(uint64 => address) public chainReceivers;
    
    /// @notice Counter for unique message IDs
    uint256 public messageCounter;
    
    /// @notice LINK token address for fee payment
    address public linkToken;

    /// @notice Router owner for configuration
    address public owner;

    /// @notice Chain selector used as source by this router instance
    uint64 public currentChainSelector;

    modifier onlyOwner() {
        require(msg.sender == owner, "MockCCIPRouter: caller is not owner");
        _;
    }
    
    /// @notice Event when message is "sent"
    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
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

    /// @notice Event when delivery failed
    event MessageFailed(
        bytes32 indexed messageId,
        address receiver,
        string reason
    );

    event OwnerSet(address indexed owner);
    event ChainSelectorSet(uint64 indexed sourceChainSelector);
    event LaneSet(uint64 indexed sourceChainSelector, uint64 indexed destinationChainSelector, bool enabled);
    event TokenMappingSet(uint64 indexed destinationChainSelector, address indexed sourceToken, address indexed destinationToken);
    event ReceiverSet(uint64 indexed destinationChainSelector, address indexed receiver);
    
    constructor(address _linkToken) {
        owner = msg.sender;
        linkToken = _linkToken;
        currentChainSelector = CCIPClient.ETHEREUM_SEPOLIA;

        // Set default mock fees for common test chains
        mockFees[10344971235874465080] = 0.01 ether; // Base Sepolia
        mockFees[16015286601757825753] = 0.015 ether; // Ethereum Sepolia

        emit OwnerSet(owner);
        emit ChainSelectorSet(currentChainSelector);
    }
    
    /**
     * @notice Set mock fee for a chain
     */
    function setMockFee(uint64 chainSelector, uint256 fee) external onlyOwner {
        mockFees[chainSelector] = fee;
    }

    function setOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "MockCCIPRouter: owner zero address");
        owner = newOwner;
        emit OwnerSet(newOwner);
    }

    function setCurrentChainSelector(uint64 sourceChainSelector) external onlyOwner {
        require(sourceChainSelector != 0, "MockCCIPRouter: source selector zero");
        currentChainSelector = sourceChainSelector;
        emit ChainSelectorSet(sourceChainSelector);
    }

    function setLane(uint64 sourceChainSelector, uint64 destinationChainSelector, bool enabled) external onlyOwner {
        lanes[sourceChainSelector][destinationChainSelector] = enabled;
        emit LaneSet(sourceChainSelector, destinationChainSelector, enabled);
    }

    function setTokenMapping(
        uint64 destinationChainSelector,
        address sourceToken,
        address destinationToken
    ) external onlyOwner {
        require(sourceToken != address(0), "MockCCIPRouter: source token zero address");
        tokenMappings[destinationChainSelector][sourceToken] = destinationToken;
        emit TokenMappingSet(destinationChainSelector, sourceToken, destinationToken);
    }

    function setReceiver(uint64 destinationChainSelector, address receiver) external onlyOwner {
        chainReceivers[destinationChainSelector] = receiver;
        emit ReceiverSet(destinationChainSelector, receiver);
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
        uint64 sourceChainSelector = currentChainSelector;
        if (sourceChainSelector == 0) {
            sourceChainSelector = _inferSourceChainSelector(destinationChainSelector);
        }
        require(lanes[sourceChainSelector][destinationChainSelector], "MockCCIPRouter: lane not enabled");

        messageCounter++;
        messageId = keccak256(abi.encodePacked(
            messageCounter,
            msg.sender,
            destinationChainSelector,
            block.timestamp
        ));
        
        // Store token amounts and burn on source
        CCIPClient.EVMTokenAmount[] memory tokens = new CCIPClient.EVMTokenAmount[](message.tokenAmounts.length);
        for (uint i = 0; i < message.tokenAmounts.length; i++) {
            require(message.tokenAmounts[i].amount > 0, "MockCCIPRouter: token amount must be > 0");
            require(
                tokenMappings[destinationChainSelector][message.tokenAmounts[i].token] != address(0),
                "MockCCIPRouter: token mapping not set"
            );

            tokens[i] = CCIPClient.EVMTokenAmount({
                token: message.tokenAmounts[i].token,
                amount: message.tokenAmounts[i].amount
            });

            IMockBridgeToken(tokens[i].token).bridgeBurn(msg.sender, tokens[i].amount);
        }
        
        // If paying with LINK, pull fee
        if (message.feeToken != address(0)) {
            uint256 fee = mockFees[destinationChainSelector];
            IERC20(message.feeToken).transferFrom(msg.sender, address(this), fee);
        } else {
            // ETH payment
            require(msg.value >= mockFees[destinationChainSelector], "Insufficient fee");
        }
        
        messages[messageId] = StoredMessage({
            sourceChainSelector: sourceChainSelector,
            destinationChainSelector: destinationChainSelector,
            sender: msg.sender,
            receiver: message.receiver,
            data: message.data,
            tokenAmounts: tokens,
            extraArgs: message.extraArgs,
            feeToken: message.feeToken,
            timestamp: block.timestamp
        });
        messageStatus[messageId] = MessageStatus.Pending;
        
        emit MessageSent(messageId, sourceChainSelector, destinationChainSelector, msg.sender, _decodeReceiver(message.receiver));
        
        return messageId;
    }
    
    /**
     * @notice Deliver a stored message to the receiver (test helper)
     * @dev This simulates CCIP delivering the message on the destination chain
     */
    function deliverMessage(bytes32 messageId) external {
        _deliverMessage(messageId, 0, false);
    }
    
    /**
     * @notice Deliver with specific source chain (for testing different scenarios)
     */
    function deliverMessageWithSource(bytes32 messageId, uint64 sourceChainSelector) external {
        _deliverMessage(messageId, sourceChainSelector, true);
    }

    /**
     * @notice Retry a previously failed message.
     */
    function retryFailedMessage(bytes32 messageId) external {
        require(messageStatus[messageId] == MessageStatus.Failed, "MockCCIPRouter: message not failed");
        _deliverMessage(messageId, 0, false);
    }

    function _deliverMessage(bytes32 messageId, uint64 sourceChainSelector, bool overrideSource) internal {
        StoredMessage storage stored = messages[messageId];
        require(stored.timestamp > 0, "Message not found");
        require(messageStatus[messageId] != MessageStatus.Delivered, "MockCCIPRouter: already delivered");
        require(
            messageStatus[messageId] == MessageStatus.Pending || messageStatus[messageId] == MessageStatus.Failed,
            "MockCCIPRouter: invalid status"
        );

        address receiver = _decodeReceiver(stored.receiver);
        address expectedReceiver = chainReceivers[stored.destinationChainSelector];
        if (expectedReceiver != address(0)) {
            require(expectedReceiver == receiver, "MockCCIPRouter: receiver mismatch");
        }

        uint64 resolvedSource = overrideSource ? sourceChainSelector : stored.sourceChainSelector;
        if (resolvedSource == 0) {
            resolvedSource = _inferSourceChainSelector(stored.destinationChainSelector);
        }

        CCIPClient.EVMTokenAmount[] memory destTokenAmounts = new CCIPClient.EVMTokenAmount[](stored.tokenAmounts.length);
        for (uint i = 0; i < stored.tokenAmounts.length; i++) {
            address sourceToken = stored.tokenAmounts[i].token;
            address destinationToken = tokenMappings[stored.destinationChainSelector][sourceToken];
            require(destinationToken != address(0), "MockCCIPRouter: destination token missing");

            uint256 amount = stored.tokenAmounts[i].amount;
            IMockBridgeToken(destinationToken).bridgeMint(receiver, amount);
            destTokenAmounts[i] = CCIPClient.EVMTokenAmount({token: destinationToken, amount: amount});
        }

        CCIPClient.Any2EVMMessage memory message = CCIPClient.Any2EVMMessage({
            messageId: messageId,
            sourceChainSelector: resolvedSource,
            sender: abi.encode(stored.sender),
            data: stored.data,
            destTokenAmounts: destTokenAmounts
        });

        (bool success, bytes memory reason) = receiver.call(
            abi.encodeWithSignature("ccipReceive((bytes32,uint64,bytes,bytes,(address,uint256)[]))", message)
        );
        if (!success) {
            for (uint i = 0; i < destTokenAmounts.length; i++) {
                if (destTokenAmounts[i].amount == 0) continue;
                try IMockBridgeToken(destTokenAmounts[i].token).bridgeBurn(receiver, destTokenAmounts[i].amount) {} catch {}
            }
            messageStatus[messageId] = MessageStatus.Failed;
            string memory failureReason = _decodeRevertReason(reason);
            messageFailureReason[messageId] = failureReason;
            emit MessageFailed(messageId, receiver, failureReason);
            return;
        }

        messageStatus[messageId] = MessageStatus.Delivered;
        delete messageFailureReason[messageId];
        emit MessageDelivered(messageId, receiver, destTokenAmounts.length);
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
     * @notice Infer a source chain selector for local tests.
     */
    function _inferSourceChainSelector(uint64 destChain) internal pure returns (uint64) {
        if (destChain == CCIPClient.BASE_SEPOLIA) return CCIPClient.ETHEREUM_SEPOLIA;
        if (destChain == CCIPClient.ETHEREUM_SEPOLIA) return CCIPClient.BASE_SEPOLIA;
        return 12345; // default
    }

    function _decodeRevertReason(bytes memory revertData) internal pure returns (string memory) {
        if (revertData.length < 4) {
            return "delivery reverted";
        }

        bytes4 selector;
        assembly {
            selector := mload(add(revertData, 32))
        }

        if (selector == bytes4(0x08c379a0)) {
            return "error(string)";
        }
        if (selector == bytes4(0x4e487b71)) {
            return "panic";
        }
        return "custom error";
    }
}
