// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockCCIPRouter} from "../../src/mocks/MockCCIPRouter.sol";
import {CCIPClient} from "../../src/reprieve/libs/CCIPClient.sol";

contract MockRouterReceiver {
    bool public shouldRevert;
    bytes32 public lastMessageId;
    uint64 public lastSourceSelector;
    address public lastToken;
    uint256 public lastAmount;

    function setShouldRevert(bool value) external {
        shouldRevert = value;
    }

    function ccipReceive(CCIPClient.Any2EVMMessage calldata message) external {
        if (shouldRevert) {
            revert("receiver revert");
        }

        lastMessageId = message.messageId;
        lastSourceSelector = message.sourceChainSelector;
        if (message.destTokenAmounts.length > 0) {
            lastToken = message.destTokenAmounts[0].token;
            lastAmount = message.destTokenAmounts[0].amount;
        }
    }
}

contract MockCCIPRouterTest is Test {
    uint64 internal constant SOURCE_CHAIN_SELECTOR = 16015286601757825753; // Ethereum Sepolia
    uint64 internal constant DEST_CHAIN_SELECTOR = 10344971235874465080; // Base Sepolia

    MockERC20 internal sourceToken;
    MockERC20 internal destinationToken;
    MockERC20 internal linkToken;
    MockCCIPRouter internal router;
    MockRouterReceiver internal receiver;

    address internal minter;
    address internal sender;

    function setUp() public {
        minter = makeAddr("minter");
        sender = makeAddr("sender");

        sourceToken = new MockERC20("Source", "SRC", 18, minter);
        destinationToken = new MockERC20("Destination", "DST", 18, minter);
        linkToken = new MockERC20("Link", "LINK", 18, minter);
        receiver = new MockRouterReceiver();
        router = new MockCCIPRouter(address(linkToken));

        router.setCurrentChainSelector(SOURCE_CHAIN_SELECTOR);
        router.setLane(SOURCE_CHAIN_SELECTOR, DEST_CHAIN_SELECTOR, true);
        router.setTokenMapping(DEST_CHAIN_SELECTOR, address(sourceToken), address(destinationToken));
        router.setReceiver(DEST_CHAIN_SELECTOR, address(receiver));

        vm.prank(minter);
        sourceToken.setBridgeBurner(address(router), true);
        vm.prank(minter);
        destinationToken.setBridgeMinter(address(router), true);
        vm.prank(minter);
        destinationToken.setBridgeBurner(address(router), true);

        vm.prank(minter);
        sourceToken.mint(sender, 100 ether);
        vm.deal(sender, 1 ether);
    }

    function test_ccipSend_BurnsSourceAndStoresPending() public {
        uint256 senderBalanceBefore = sourceToken.balanceOf(sender);
        uint256 sourceSupplyBefore = sourceToken.totalSupply();

        bytes32 messageId = _sendMessage(10 ether);

        assertEq(sourceToken.balanceOf(sender), senderBalanceBefore - 10 ether);
        assertEq(sourceToken.totalSupply(), sourceSupplyBefore - 10 ether);
        assertEq(uint256(router.messageStatus(messageId)), uint256(MockCCIPRouter.MessageStatus.Pending));

        MockCCIPRouter.StoredMessage memory stored = router.getMessage(messageId);
        assertEq(stored.sourceChainSelector, SOURCE_CHAIN_SELECTOR);
        assertEq(stored.destinationChainSelector, DEST_CHAIN_SELECTOR);
        assertEq(stored.tokenAmounts[0].token, address(sourceToken));
        assertEq(stored.tokenAmounts[0].amount, 10 ether);
    }

    function test_deliverMessage_MintsDestinationAndMarksDelivered() public {
        uint256 destinationSupplyBefore = destinationToken.totalSupply();
        bytes32 messageId = _sendMessage(7 ether);

        router.deliverMessage(messageId);

        assertEq(uint256(router.messageStatus(messageId)), uint256(MockCCIPRouter.MessageStatus.Delivered));
        assertEq(destinationToken.totalSupply(), destinationSupplyBefore + 7 ether);
        assertEq(destinationToken.balanceOf(address(receiver)), 7 ether);
        assertEq(receiver.lastMessageId(), messageId);
        assertEq(receiver.lastSourceSelector(), SOURCE_CHAIN_SELECTOR);
        assertEq(receiver.lastToken(), address(destinationToken));
        assertEq(receiver.lastAmount(), 7 ether);
    }

    function test_deliverMessage_RevertingReceiverMarksFailedAndRetrySucceeds() public {
        bytes32 messageId = _sendMessage(5 ether);

        receiver.setShouldRevert(true);
        router.deliverMessage(messageId);

        assertEq(uint256(router.messageStatus(messageId)), uint256(MockCCIPRouter.MessageStatus.Failed));
        assertEq(destinationToken.balanceOf(address(receiver)), 0);

        receiver.setShouldRevert(false);
        router.retryFailedMessage(messageId);

        assertEq(uint256(router.messageStatus(messageId)), uint256(MockCCIPRouter.MessageStatus.Delivered));
        assertEq(destinationToken.balanceOf(address(receiver)), 5 ether);
    }

    function test_ccipSend_RevertsWhenLaneDisabled() public {
        router.setLane(SOURCE_CHAIN_SELECTOR, DEST_CHAIN_SELECTOR, false);

        vm.prank(sender);
        vm.expectRevert("MockCCIPRouter: lane not enabled");
        router.ccipSend{value: 0.01 ether}(DEST_CHAIN_SELECTOR, _buildMessage(1 ether));
    }

    function test_ccipSend_RevertsWhenTokenMappingMissing() public {
        router.setTokenMapping(DEST_CHAIN_SELECTOR, address(sourceToken), address(0));

        vm.prank(sender);
        vm.expectRevert("MockCCIPRouter: token mapping not set");
        router.ccipSend{value: 0.01 ether}(DEST_CHAIN_SELECTOR, _buildMessage(1 ether));
    }

    function test_deliverExternalMessage_Succeeds() public {
        bytes32 messageId = keccak256("external-message");
        address externalSender = makeAddr("externalSender");
        bytes memory payload = abi.encode(uint256(1337));
        uint256 amount = 3 ether;

        uint256 supplyBefore = destinationToken.totalSupply();
        router.deliverExternalMessage(
            messageId,
            SOURCE_CHAIN_SELECTOR,
            externalSender,
            address(receiver),
            payload,
            address(destinationToken),
            amount
        );

        assertEq(uint256(router.messageStatus(messageId)), uint256(MockCCIPRouter.MessageStatus.Delivered));
        assertEq(destinationToken.totalSupply(), supplyBefore + amount);
        assertEq(destinationToken.balanceOf(address(receiver)), amount);
        assertEq(receiver.lastMessageId(), messageId);
        assertEq(receiver.lastSourceSelector(), SOURCE_CHAIN_SELECTOR);
        assertEq(receiver.lastToken(), address(destinationToken));
        assertEq(receiver.lastAmount(), amount);
    }

    function test_deliverExternalMessage_RevertingReceiverMarksFailed() public {
        bytes32 messageId = keccak256("external-message-revert");
        address externalSender = makeAddr("externalSender");
        bytes memory payload = abi.encode(uint256(2026));
        uint256 amount = 2 ether;

        receiver.setShouldRevert(true);
        router.deliverExternalMessage(
            messageId,
            SOURCE_CHAIN_SELECTOR,
            externalSender,
            address(receiver),
            payload,
            address(destinationToken),
            amount
        );

        assertEq(uint256(router.messageStatus(messageId)), uint256(MockCCIPRouter.MessageStatus.Failed));
        assertEq(destinationToken.balanceOf(address(receiver)), 0);
    }

    function test_deliverExternalMessage_OnlyOwner() public {
        vm.prank(sender);
        vm.expectRevert("MockCCIPRouter: caller is not owner");
        router.deliverExternalMessage(
            keccak256("not-owner"),
            SOURCE_CHAIN_SELECTOR,
            sender,
            address(receiver),
            abi.encode(uint256(1)),
            address(destinationToken),
            1 ether
        );
    }

    function _sendMessage(uint256 amount) internal returns (bytes32) {
        CCIPClient.EVM2AnyMessage memory message = _buildMessage(amount);
        uint256 fee = router.getFee(DEST_CHAIN_SELECTOR, message);

        vm.prank(sender);
        return router.ccipSend{value: fee}(DEST_CHAIN_SELECTOR, message);
    }

    function _buildMessage(uint256 amount) internal view returns (CCIPClient.EVM2AnyMessage memory message) {
        CCIPClient.EVMTokenAmount[] memory tokenAmounts = new CCIPClient.EVMTokenAmount[](1);
        tokenAmounts[0] = CCIPClient.EVMTokenAmount({token: address(sourceToken), amount: amount});

        message = CCIPClient.EVM2AnyMessage({
            receiver: abi.encode(address(receiver)),
            data: abi.encode(uint256(42)),
            tokenAmounts: tokenAmounts,
            feeToken: address(0),
            extraArgs: bytes("")
        });
    }
}
