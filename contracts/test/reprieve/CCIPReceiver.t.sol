// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {CCIPReceiver} from "../../src/reprieve/CCIPReceiver.sol";
import {RescueExecutor} from "../../src/reprieve/RescueExecutor.sol";
import {RescueEscrow} from "../../src/reprieve/RescueEscrow.sol";
import {RescueLog} from "../../src/reprieve/RescueLog.sol";
import {AdapterRegistry} from "../../src/reprieve/AdapterRegistry.sol";
import {CCIPClient} from "../../src/reprieve/libs/CCIPClient.sol";
import {ReprieveTypes} from "../../src/reprieve/libs/ReprieveTypes.sol";
import {ReprieveErrors} from "../../src/reprieve/libs/ReprieveErrors.sol";
import {ReprieveEvents} from "../../src/reprieve/libs/ReprieveEvents.sol";

/**
 * @title CCIPReceiverTest
 * @notice Slide 6 validation: CCIP Receiver (Cross-Chain Core)
 * @dev Tests programmable token transfers with data following CCIP dev guide
 */
contract CCIPReceiverTest is Test {
    // Events for testing
    event MessageReceived(bytes32 indexed messageId, uint64 indexed sourceChainSelector, address sender);
    event ExecutorSet(address executor);
    event RouterSet(address router);
    event SourceChainAllowed(uint64 chainSelector, bool allowed);
    event SenderAllowed(uint64 chainSelector, address sender, bool allowed);
    event MessageFailed(bytes32 indexed messageId, uint64 indexed sourceChainSelector, bytes32 indexed execId, string reason);
    event MessageRecovered(bytes32 indexed messageId, bytes32 indexed execId);
    
    CCIPReceiver ccipReceiver;
    RescueExecutor executor;
    RescueEscrow rescueEscrow;
    RescueLog rescueLog;
    AdapterRegistry adapterRegistry;
    MockERC20 token;
    
    address owner;
    address router;
    address user;
    address sourceSender;
    address notAuthorized;
    address minter;
    
    uint64 constant SOURCE_CHAIN_SELECTOR = 16015286601757825753; // Arbitrum Sepolia
    uint64 constant DEST_CHAIN_SELECTOR = 10344971235874465080;   // Base Sepolia
    bytes32 constant MESSAGE_ID = keccak256("test-message-1");
    bytes32 constant EXEC_ID = keccak256("test-exec-1");
    
    function setUp() public {
        owner = address(this);
        router = makeAddr("ccipRouter");
        user = makeAddr("user");
        sourceSender = makeAddr("sourceSender");
        notAuthorized = makeAddr("notAuthorized");
        minter = makeAddr("minter");
        
        // Deploy mock token
        token = new MockERC20("TEST", "TEST", 18, minter);
        
        // Deploy Reprieve contracts
        rescueLog = new RescueLog(owner);
        rescueEscrow = new RescueEscrow(owner, address(rescueLog));
        adapterRegistry = new AdapterRegistry(owner);
        adapterRegistry.initializeDemoProtocols();
        
        executor = new RescueExecutor(owner, address(rescueLog), address(rescueEscrow), address(adapterRegistry));
        
        ccipReceiver = new CCIPReceiver(owner, address(executor), address(rescueEscrow), address(rescueLog));
        
        // Authorizations
        rescueLog.setAuthorizedWriter(address(executor), true);
        rescueLog.setAuthorizedWriter(address(ccipReceiver), true);
        rescueEscrow.setAuthorizedDepositor(address(ccipReceiver), true);
        ccipReceiver.setRouter(router);
        
        // Mint tokens for testing (simulating CCIP transfer)
        vm.prank(minter);
        token.mint(address(ccipReceiver), 10000 ether);
    }
    
    // ============ AUTHORIZATION TESTS ============
    
    function test_SetRouter() public {
        address newRouter = makeAddr("newRouter");
        ccipReceiver.setRouter(newRouter);
        assertEq(ccipReceiver.ccipRouter(), newRouter);
    }
    
    function test_SetRouter_OnlyOwner() public {
        vm.prank(notAuthorized);
        vm.expectRevert();
        ccipReceiver.setRouter(notAuthorized);
    }
    
    function test_SetRouter_ZeroAddressReverts() public {
        vm.expectRevert(ReprieveErrors.ZeroAddress.selector);
        ccipReceiver.setRouter(address(0));
    }
    
    function test_SetExecutor() public {
        address newExecutor = makeAddr("newExecutor");
        ccipReceiver.setExecutor(newExecutor);
        assertEq(address(ccipReceiver.executor()), newExecutor);
    }
    
    function test_SetExecutor_OnlyOwner() public {
        vm.prank(notAuthorized);
        vm.expectRevert();
        ccipReceiver.setExecutor(notAuthorized);
    }
    
    // ============ SOURCE CHAIN TESTS ============
    
    function test_SetAllowedSourceChain() public {
        vm.expectEmit(true, false, false, true);
        emit SourceChainAllowed(SOURCE_CHAIN_SELECTOR, true);
        
        ccipReceiver.setAllowedSourceChain(SOURCE_CHAIN_SELECTOR, true);
        assertTrue(ccipReceiver.allowedSourceChains(SOURCE_CHAIN_SELECTOR));
    }
    
    function test_SetAllowedSourceChain_Revoke() public {
        ccipReceiver.setAllowedSourceChain(SOURCE_CHAIN_SELECTOR, true);
        ccipReceiver.setAllowedSourceChain(SOURCE_CHAIN_SELECTOR, false);
        assertFalse(ccipReceiver.allowedSourceChains(SOURCE_CHAIN_SELECTOR));
    }
    
    function test_SetAllowedSourceChain_OnlyOwner() public {
        vm.prank(notAuthorized);
        vm.expectRevert();
        ccipReceiver.setAllowedSourceChain(SOURCE_CHAIN_SELECTOR, true);
    }
    
    // ============ SENDER TESTS ============
    
    function test_SetAllowedSender() public {
        vm.expectEmit(true, true, false, true);
        emit SenderAllowed(SOURCE_CHAIN_SELECTOR, sourceSender, true);
        
        ccipReceiver.setAllowedSender(SOURCE_CHAIN_SELECTOR, sourceSender, true);
        assertTrue(ccipReceiver.allowedSenders(SOURCE_CHAIN_SELECTOR, sourceSender));
    }
    
    function test_SetAllowedSender_OnlyOwner() public {
        vm.prank(notAuthorized);
        vm.expectRevert();
        ccipReceiver.setAllowedSender(SOURCE_CHAIN_SELECTOR, sourceSender, true);
    }
    
    // ============ CCIP RECEIVE VALIDATION TESTS ============
    
    function test_CcipReceive_InvalidRouterReverts() public {
        ccipReceiver.setAllowedSourceChain(SOURCE_CHAIN_SELECTOR, true);
        
        CCIPClient.Any2EVMMessage memory message = _buildMessage(
            MESSAGE_ID,
            SOURCE_CHAIN_SELECTOR,
            sourceSender,
            1000 ether
        );
        
        // Call from non-router
        vm.prank(notAuthorized);
        vm.expectRevert(ReprieveErrors.CCIPRouterNotSet.selector);
        ccipReceiver.ccipReceive(message);
    }
    
    function test_CcipReceive_SourceNotAllowedReverts() public {
        ccipReceiver.setAllowedSender(SOURCE_CHAIN_SELECTOR, sourceSender, true);
        
        CCIPClient.Any2EVMMessage memory message = _buildMessage(
            MESSAGE_ID,
            SOURCE_CHAIN_SELECTOR,
            sourceSender,
            1000 ether
        );
        
        vm.prank(router);
        vm.expectRevert(abi.encodeWithSelector(ReprieveErrors.CCIPSourceNotAllowed.selector, SOURCE_CHAIN_SELECTOR));
        ccipReceiver.ccipReceive(message);
    }
    
    function test_CcipReceive_SenderNotAllowedReverts() public {
        ccipReceiver.setAllowedSourceChain(SOURCE_CHAIN_SELECTOR, true);
        
        CCIPClient.Any2EVMMessage memory message = _buildMessage(
            MESSAGE_ID,
            SOURCE_CHAIN_SELECTOR,
            notAuthorized, // Not allowed sender
            1000 ether
        );
        
        vm.prank(router);
        vm.expectRevert(abi.encodeWithSelector(ReprieveErrors.CCIPSenderNotAllowed.selector, notAuthorized));
        ccipReceiver.ccipReceive(message);
    }
    
    function test_CcipReceive_DuplicateMessageReverts() public {
        ccipReceiver.setAllowedSourceChain(SOURCE_CHAIN_SELECTOR, true);
        ccipReceiver.setAllowedSender(SOURCE_CHAIN_SELECTOR, sourceSender, true);
        
        bytes32 uniqueMessageId = keccak256("duplicate-test-msg");
        
        // Build message with valid deadline
        ReprieveTypes.CCIPMessage memory rescueMessage = ReprieveTypes.CCIPMessage({
            execId: EXEC_ID,
            user: user,
            mode: ReprieveTypes.RescueMode.TOP_UP,
            targetAdapter: address(0),
            asset: address(token),
            amount: 1000 ether,
            timestamp: block.timestamp,
            deadline: block.timestamp + 1 hours
        });
        
        CCIPClient.Any2EVMMessage memory message = _buildMessageWithData(
            uniqueMessageId,
            SOURCE_CHAIN_SELECTOR,
            sourceSender,
            1000 ether,
            abi.encode(rescueMessage)
        );
        message.destTokenAmounts[0].token = address(token);
        
        // Mint tokens
        vm.prank(minter);
        token.mint(address(ccipReceiver), 2000 ether);
        
        // First receive
        vm.prank(router);
        ccipReceiver.ccipReceive(message);
        
        // Verify first message was processed
        assertTrue(ccipReceiver.processedMessages(uniqueMessageId));
        
        // Second receive with same message ID should revert
        vm.prank(router);
        vm.expectRevert(ReprieveErrors.CCIPMessageInvalid.selector);
        ccipReceiver.ccipReceive(message);
    }
    
    // ============ CCIP RECEIVE PROCESSING TESTS ============
    
    function test_CcipReceive_ProcessesMessage() public {
        ccipReceiver.setAllowedSourceChain(SOURCE_CHAIN_SELECTOR, true);
        ccipReceiver.setAllowedSender(SOURCE_CHAIN_SELECTOR, sourceSender, true);
        
        bytes32 uniqueMessageId = keccak256("process-test");
        
        // Build message with valid future deadline
        ReprieveTypes.CCIPMessage memory rescueMessage = ReprieveTypes.CCIPMessage({
            execId: EXEC_ID,
            user: user,
            mode: ReprieveTypes.RescueMode.TOP_UP,
            targetAdapter: address(0),
            asset: address(token),
            amount: 1000 ether,
            timestamp: block.timestamp,
            deadline: block.timestamp + 1 hours
        });
        
        CCIPClient.Any2EVMMessage memory message = _buildMessageWithData(
            uniqueMessageId,
            SOURCE_CHAIN_SELECTOR,
            sourceSender,
            1000 ether,
            abi.encode(rescueMessage)
        );
        // Update token address in the message
        message.destTokenAmounts[0].token = address(token);
        
        // Mint tokens to receiver (simulating CCIP token transfer)
        vm.prank(minter);
        token.mint(address(ccipReceiver), 1000 ether);
        
        vm.prank(router);
        ccipReceiver.ccipReceive(message);
        
        assertTrue(ccipReceiver.processedMessages(uniqueMessageId));
    }
    
    function test_CcipReceive_DeadlinePassed_HandlesFailure() public {
        ccipReceiver.setAllowedSourceChain(SOURCE_CHAIN_SELECTOR, true);
        ccipReceiver.setAllowedSender(SOURCE_CHAIN_SELECTOR, sourceSender, true);
        
        // Warp to future first to avoid underflow
        vm.warp(2 hours + 100);
        
        // Build message with past deadline
        ReprieveTypes.CCIPMessage memory rescueMessage = ReprieveTypes.CCIPMessage({
            execId: EXEC_ID,
            user: user,
            mode: ReprieveTypes.RescueMode.TOP_UP,
            targetAdapter: address(0),
            asset: address(token),
            amount: 1000 ether,
            timestamp: 100, // 100 seconds
            deadline: 1 hours // Past deadline
        });
        
        bytes32 msgId = keccak256("deadline-test");
        CCIPClient.Any2EVMMessage memory message = _buildMessageWithData(
            msgId,
            SOURCE_CHAIN_SELECTOR,
            sourceSender,
            1000 ether,
            abi.encode(rescueMessage)
        );
        message.destTokenAmounts[0].token = address(token);
        
        // Mint tokens
        vm.prank(minter);
        token.mint(address(ccipReceiver), 1000 ether);
        
        vm.prank(router);
        ccipReceiver.ccipReceive(message);
        
        // Message should be processed and marked as failed
        assertTrue(ccipReceiver.processedMessages(msgId));
        
        // Failed message should be stored
        CCIPReceiver.FailedMessage memory failed = ccipReceiver.getFailedMessage(msgId);
        assertEq(failed.messageId, msgId);
        assertFalse(failed.recovered);
    }
    
    // ============ FAILED MESSAGE RECOVERY TESTS ============
    
    function test_RetryFailedMessage() public {
        ccipReceiver.setAllowedSourceChain(SOURCE_CHAIN_SELECTOR, true);
        ccipReceiver.setAllowedSender(SOURCE_CHAIN_SELECTOR, sourceSender, true);
        
        // Warp to create expired message
        vm.warp(2 hours + 100);
        
        ReprieveTypes.CCIPMessage memory rescueMessage = ReprieveTypes.CCIPMessage({
            execId: EXEC_ID,
            user: user,
            mode: ReprieveTypes.RescueMode.TOP_UP,
            targetAdapter: address(0),
            asset: address(token),
            amount: 1000 ether,
            timestamp: 100,
            deadline: 1 hours
        });
        
        bytes32 msgId = keccak256("retry-test");
        CCIPClient.Any2EVMMessage memory message = _buildMessageWithData(
            msgId,
            SOURCE_CHAIN_SELECTOR,
            sourceSender,
            1000 ether,
            abi.encode(rescueMessage)
        );
        message.destTokenAmounts[0].token = address(token);
        
        // Mint tokens
        vm.prank(minter);
        token.mint(address(ccipReceiver), 1000 ether);
        
        // First receive - fails due to deadline
        vm.prank(router);
        ccipReceiver.ccipReceive(message);
        
        // Verify can retry
        assertTrue(ccipReceiver.canRetryMessage(msgId));
        
        // Retry should revert because there's no valid completion path
        // (executor doesn't have proper setup in this test)
        vm.expectRevert();
        ccipReceiver.retryFailedMessage(msgId);
    }
    
    function test_CanRetryMessage() public {
        ccipReceiver.setAllowedSourceChain(SOURCE_CHAIN_SELECTOR, true);
        ccipReceiver.setAllowedSender(SOURCE_CHAIN_SELECTOR, sourceSender, true);
        
        // Non-existent message cannot be retried
        assertFalse(ccipReceiver.canRetryMessage(keccak256("nonexistent")));
    }
    
    // ============ VIEW FUNCTION TESTS ============
    
    function test_GetExecutor() public view {
        assertEq(ccipReceiver.getExecutor(), address(executor));
    }
    
    function test_GetRouter() public view {
        assertEq(ccipReceiver.getRouter(), router);
    }
    
    function test_IsAllowedSourceChain() public {
        assertFalse(ccipReceiver.isAllowedSourceChain(SOURCE_CHAIN_SELECTOR));
        
        ccipReceiver.setAllowedSourceChain(SOURCE_CHAIN_SELECTOR, true);
        assertTrue(ccipReceiver.isAllowedSourceChain(SOURCE_CHAIN_SELECTOR));
    }
    
    function test_IsAllowedSender() public {
        assertFalse(ccipReceiver.isAllowedSender(SOURCE_CHAIN_SELECTOR, sourceSender));
        
        ccipReceiver.setAllowedSender(SOURCE_CHAIN_SELECTOR, sourceSender, true);
        assertTrue(ccipReceiver.isAllowedSender(SOURCE_CHAIN_SELECTOR, sourceSender));
    }
    
    // ============ MINIMUM GAS TESTS ============
    
    function test_MinGasForCompletion() public view {
        assertEq(ccipReceiver.MIN_GAS_FOR_COMPLETION(), 200000);
    }
    
    // ============ HELPER FUNCTIONS ============
    
    function _buildMessage(
        bytes32 messageId,
        uint64 sourceChainSelector,
        address sender,
        uint256 amount
    ) internal view returns (CCIPClient.Any2EVMMessage memory) {
        ReprieveTypes.CCIPMessage memory rescueMessage = ReprieveTypes.CCIPMessage({
            execId: EXEC_ID,
            user: user,
            mode: ReprieveTypes.RescueMode.TOP_UP,
            targetAdapter: address(0),
            asset: address(token),
            amount: amount,
            timestamp: block.timestamp,
            deadline: block.timestamp + 1 hours
        });
        
        return _buildMessageWithData(
            messageId,
            sourceChainSelector,
            sender,
            amount,
            abi.encode(rescueMessage)
        );
    }
    
    function _buildMessageWithData(
        bytes32 messageId,
        uint64 sourceChainSelector,
        address sender,
        uint256 amount,
        bytes memory data
    ) internal pure returns (CCIPClient.Any2EVMMessage memory) {
        CCIPClient.EVMTokenAmount[] memory tokenAmounts = new CCIPClient.EVMTokenAmount[](1);
        tokenAmounts[0] = CCIPClient.EVMTokenAmount({
            token: address(0), // Will be set by actual test if needed
            amount: amount
        });
        
        return CCIPClient.Any2EVMMessage({
            messageId: messageId,
            sourceChainSelector: sourceChainSelector,
            sender: abi.encodePacked(sender),
            data: data,
            destTokenAmounts: tokenAmounts
        });
    }
}
