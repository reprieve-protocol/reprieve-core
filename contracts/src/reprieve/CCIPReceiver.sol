// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {ReprieveTypes} from "./libs/ReprieveTypes.sol";
import {ReprieveErrors} from "./libs/ReprieveErrors.sol";
import {ReprieveEvents} from "./libs/ReprieveEvents.sol";
import {CCIPClient} from "./libs/CCIPClient.sol";
import {IRescueExecutor} from "./interfaces/IRescueExecutor.sol";
import {IRescueEscrow} from "./interfaces/IRescueEscrow.sol";
import {IRescueLog} from "./interfaces/IRescueLog.sol";

/**
 * @title CCIPReceiver
 * @notice Destination-chain CCIP receive handler for rescue payloads/funds
 * @dev Validates router/source selector/sender and calls executor completion path
 * @dev Follows Chainlink CCIP Receiver pattern with defensive error handling
 */
contract CCIPReceiver is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    /// @notice CCIP Router address (only router can call ccipReceive)
    address public ccipRouter;
    
    /// @notice RescueExecutor contract
    IRescueExecutor public executor;
    
    /// @notice RescueEscrow contract (for failed transfers)
    IRescueEscrow public rescueEscrow;
    
    /// @notice RescueLog contract
    IRescueLog public rescueLog;
    
    /// @notice Source chain selector => allowed
    mapping(uint64 => bool) public allowedSourceChains;
    
    /// @notice Source chain => sender => allowed
    mapping(uint64 => mapping(address => bool)) public allowedSenders;
    
    /// @notice Message ID => processed
    mapping(bytes32 => bool) public processedMessages;
    
    /// @notice Failed messages for retry
    mapping(bytes32 => FailedMessage) public failedMessages;
    
    /// @notice Extra args for CCIP receive
    bytes public extraArgs;
    
    /// @notice Minimum gas for completion callback
    uint256 public constant MIN_GAS_FOR_COMPLETION = 200000;
    
    /// @notice Failed message record
    struct FailedMessage {
        bytes32 messageId;
        bytes32 escrowId;           // Escrow ID if funds were moved to escrow
        uint64 sourceChainSelector;
        address sender;
        bytes data;
        CCIPClient.EVMTokenAmount[] tokenAmounts;
        string reason;
        uint256 timestamp;
        bool recovered;
    }
    
    /// @notice Emitted when message processing fails
    event MessageFailed(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        bytes32 indexed execId,
        string reason
    );
    
    /// @notice Emitted when failed message is recovered
    event MessageRecovered(bytes32 indexed messageId, bytes32 indexed execId);
    
    modifier onlyRouter() {
        if (msg.sender != ccipRouter) revert ReprieveErrors.CCIPRouterNotSet();
        _;
    }
    
    constructor(
        address initialOwner,
        address _executor,
        address _rescueEscrow,
        address _rescueLog
    ) Ownable(initialOwner) {
        if (_executor == address(0) || _rescueEscrow == address(0) || _rescueLog == address(0)) {
            revert ReprieveErrors.ZeroAddress();
        }
        executor = IRescueExecutor(_executor);
        rescueEscrow = IRescueEscrow(_rescueEscrow);
        rescueLog = IRescueLog(_rescueLog);
    }
    
    /**
     * @notice Set CCIP router address
     * @param _router Router address
     */
    function setRouter(address _router) external onlyOwner {
        if (_router == address(0)) revert ReprieveErrors.ZeroAddress();
        ccipRouter = _router;
        emit ReprieveEvents.CcipRouterSet(_router);
    }
    
    /**
     * @notice Set executor address
     * @param _executor Executor address
     */
    function setExecutor(address _executor) external onlyOwner {
        if (_executor == address(0)) revert ReprieveErrors.ZeroAddress();
        executor = IRescueExecutor(_executor);
        emit ReprieveEvents.ExecutorSet(_executor);
    }
    
    /**
     * @notice Allow/disallow a source chain
     * @param sourceChainSelector Chain selector
     * @param allowed True to allow
     */
    function setAllowedSourceChain(uint64 sourceChainSelector, bool allowed) external onlyOwner {
        allowedSourceChains[sourceChainSelector] = allowed;
        emit ReprieveEvents.SourceChainAllowed(sourceChainSelector, allowed);
    }
    
    /**
     * @notice Allow/disallow a sender from a source chain
     * @param sourceChainSelector Chain selector
     * @param sender Sender address
     * @param allowed True to allow
     */
    function setAllowedSender(uint64 sourceChainSelector, address sender, bool allowed) external onlyOwner {
        allowedSenders[sourceChainSelector][sender] = allowed;
        emit ReprieveEvents.SenderAllowed(sourceChainSelector, sender, allowed);
    }
    
    /**
     * @notice Set extra args for CCIP operations
     * @param _extraArgs Encoded extra arguments
     */
    function setExtraArgs(bytes calldata _extraArgs) external onlyOwner {
        extraArgs = _extraArgs;
    }
    
    /**
     * @notice Main CCIP receive function (called by Router)
     * @param message CCIP Any2EVM message
     */
    function ccipReceive(CCIPClient.Any2EVMMessage calldata message) 
        external 
        onlyRouter 
        nonReentrant 
    {
        _ccipReceive(message);
    }
    
    /**
     * @notice Internal CCIP receive implementation
     * @param message CCIP message
     */
    function _ccipReceive(CCIPClient.Any2EVMMessage memory message) internal {
        // Validate source chain
        if (!allowedSourceChains[message.sourceChainSelector]) {
            revert ReprieveErrors.CCIPSourceNotAllowed(message.sourceChainSelector);
        }
        
        // Decode sender address
        address sender = CCIPClient.bytesToAddress(message.sender);
        
        // Validate sender
        if (!allowedSenders[message.sourceChainSelector][sender]) {
            revert ReprieveErrors.CCIPSenderNotAllowed(sender);
        }
        
        // Check message not already processed
        if (processedMessages[message.messageId]) {
            revert ReprieveErrors.CCIPMessageInvalid();
        }
        
        // Mark as processed
        processedMessages[message.messageId] = true;
        
        // Decode rescue message data
        ReprieveTypes.CCIPMessage memory rescueMessage = abi.decode(message.data, (ReprieveTypes.CCIPMessage));
        
        // Validate deadline
        if (block.timestamp > rescueMessage.deadline) {
            _handleFailedReceive(message, rescueMessage, "Deadline passed");
            return;
        }
        
        // Check gas
        if (gasleft() < MIN_GAS_FOR_COMPLETION) {
            _handleFailedReceive(message, rescueMessage, "Insufficient gas");
            return;
        }
        
        // Attempt to complete cross-chain leg with try/catch for safety
        try this._tryCompleteRescue(message, rescueMessage) returns (bool success) {
            if (success) {
                // Log success (wrapped in try/catch)
                try rescueLog.logRescueCompleted(
                    rescueMessage.execId,
                    rescueMessage.user,
                    ReprieveTypes.RescueStatus.Completed,
                    "Cross-chain rescue completed"
                ) {} catch {}
                
                emit ReprieveEvents.CrossChainCompleted(
                    rescueMessage.execId,
                    message.messageId,
                    rescueMessage.amount
                );
            } else {
                // Completion returned false - store for manual recovery
                _handleFailedReceive(message, rescueMessage, "Completion returned false");
            }
        } catch (bytes memory reason) {
            // Exception during completion - store for manual recovery
            _handleFailedReceive(message, rescueMessage, _bytesToString(reason));
        }
    }
    
    /**
     * @notice Try to complete rescue (external for try/catch)
     * @param message CCIP message
     * @param rescueMessage Decoded rescue payload
     * @return success Whether completion succeeded
     */
    function _tryCompleteRescue(
        CCIPClient.Any2EVMMessage memory message,
        ReprieveTypes.CCIPMessage memory rescueMessage
    ) external returns (bool) {
        require(msg.sender == address(this), "Only self");
        
        // Get token from message
        if (message.destTokenAmounts.length == 0) {
            return false;
        }
        
        CCIPClient.EVMTokenAmount memory tokenAmount = message.destTokenAmounts[0];
        
        // Approve executor to spend tokens
        IERC20(tokenAmount.token).approve(address(executor), tokenAmount.amount);
        
        // Use the actually delivered destination token/amount for execution.
        // Payload asset address may be source-chain token and can differ cross-chain.
        return executor.completeCrossChainLeg(
            rescueMessage.execId,
            rescueMessage.user,
            rescueMessage.targetAdapter,
            rescueMessage.mode,
            tokenAmount.token,
            tokenAmount.amount
        );
    }
    
    /**
     * @notice Retry a failed message (manual recovery)
     * @param messageId Failed message ID
     */
    function retryFailedMessage(bytes32 messageId) external onlyOwner nonReentrant {
        FailedMessage storage failedMsg = failedMessages[messageId];
        
        if (failedMsg.messageId == bytes32(0)) {
            revert ReprieveErrors.CCIPMessageInvalid();
        }
        
        if (failedMsg.recovered) {
            revert ReprieveErrors.CCIPMessageInvalid();
        }
        
        // Mark as recovered
        failedMsg.recovered = true;
        
        // Reconstruct message and try again
        CCIPClient.Any2EVMMessage memory message = CCIPClient.Any2EVMMessage({
            messageId: failedMsg.messageId,
            sourceChainSelector: failedMsg.sourceChainSelector,
            sender: abi.encodePacked(failedMsg.sender),
            data: failedMsg.data,
            destTokenAmounts: failedMsg.tokenAmounts
        });
        
        ReprieveTypes.CCIPMessage memory rescueMessage = abi.decode(failedMsg.data, (ReprieveTypes.CCIPMessage));
        
        // Try completion again
        try this._tryCompleteRescue(message, rescueMessage) returns (bool success) {
            if (success) {
                emit MessageRecovered(messageId, rescueMessage.execId);
            } else {
                revert ReprieveErrors.CrossChainTransferFailed();
            }
        } catch {
            revert ReprieveErrors.CrossChainTransferFailed();
        }
    }
    
    /**
     * @notice Handle failed receive by moving to escrow
     * @param message CCIP message
     * @param rescueMessage Rescue payload
     * @param reason Failure reason
     */
    function _handleFailedReceive(
        CCIPClient.Any2EVMMessage memory message,
        ReprieveTypes.CCIPMessage memory rescueMessage,
        string memory reason
    ) internal {
        // Generate escrow ID
        bytes32 escrowId = keccak256(abi.encodePacked(message.messageId, block.timestamp));
        
        // Get token from message
        if (message.destTokenAmounts.length > 0) {
            CCIPClient.EVMTokenAmount memory tokenAmount = message.destTokenAmounts[0];
            
            // Approve escrow to pull tokens
            IERC20(tokenAmount.token).approve(address(rescueEscrow), tokenAmount.amount);
            
            // Deposit to escrow
            try rescueEscrow.depositFailedTransfer(
                escrowId,
                rescueMessage.user,
                tokenAmount.token,
                tokenAmount.amount,
                message.sourceChainSelector,
                block.chainid,
                rescueMessage.execId
            ) {
                // Success
            } catch {
                // If escrow deposit fails, tokens remain in this contract
                // Owner can recover via emergencyWithdraw
            }
        }
        
        // Store failed message for retry
        CCIPClient.EVMTokenAmount[] memory storedTokens = new CCIPClient.EVMTokenAmount[](message.destTokenAmounts.length);
        for (uint256 i = 0; i < message.destTokenAmounts.length; i++) {
            storedTokens[i] = message.destTokenAmounts[i];
        }
        
        failedMessages[message.messageId] = FailedMessage({
            messageId: message.messageId,
            escrowId: escrowId,
            sourceChainSelector: message.sourceChainSelector,
            sender: CCIPClient.bytesToAddress(message.sender),
            data: message.data,
            tokenAmounts: storedTokens,
            reason: reason,
            timestamp: block.timestamp,
            recovered: false
        });
        
        // Log failure (wrapped in try/catch)
        try rescueLog.logRescueFailed(
            rescueMessage.execId,
            rescueMessage.user,
            string.concat("Cross-chain failed: ", reason)
        ) {} catch {}
        
        emit MessageFailed(
            message.messageId,
            message.sourceChainSelector,
            rescueMessage.execId,
            reason
        );
        
        emit ReprieveEvents.CrossChainDestinationFailed(
            rescueMessage.execId,
            message.messageId,
            reason
        );
    }
    
    /**
     * @notice Get failed message details
     * @param messageId Message ID
     * @return FailedMessage struct
     */
    function getFailedMessage(bytes32 messageId) external view returns (FailedMessage memory) {
        return failedMessages[messageId];
    }
    
    /**
     * @notice Check if message can be retried
     * @param messageId Message ID
     * @return True if can be retried
     */
    function canRetryMessage(bytes32 messageId) external view returns (bool) {
        FailedMessage memory msg_ = failedMessages[messageId];
        return msg_.messageId != bytes32(0) && !msg_.recovered;
    }
    
    /**
     * @notice Emergency withdrawal for stuck tokens
     * @param token Token address
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }
    
    // ============ View Functions ============
    
    function getExecutor() external view returns (address) {
        return address(executor);
    }
    
    function getRouter() external view returns (address) {
        return ccipRouter;
    }
    
    function isAllowedSourceChain(uint64 chainSelector) external view returns (bool) {
        return allowedSourceChains[chainSelector];
    }
    
    function isAllowedSender(uint64 chainSelector, address sender) external view returns (bool) {
        return allowedSenders[chainSelector][sender];
    }
    
    // ============ Internal Helpers ============
    
    function _bytesToString(bytes memory data) internal pure returns (string memory) {
        if (data.length <= 64) {
            return "Unknown error";
        }
        // Skip first 64 bytes (pointer and length)
        bytes memory result = new bytes(data.length - 64);
        for (uint256 i = 64; i < data.length; i++) {
            result[i - 64] = data[i];
        }
        return string(result);
    }
    
    /**
     * @notice Receive native tokens
     */
    receive() external payable {}
}
