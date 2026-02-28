// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {RescueEscrow} from "../../src/reprieve/RescueEscrow.sol";
import {RescueLog} from "../../src/reprieve/RescueLog.sol";
import {ReprieveTypes} from "../../src/reprieve/libs/ReprieveTypes.sol";
import {ReprieveErrors} from "../../src/reprieve/libs/ReprieveErrors.sol";
import {ReprieveEvents} from "../../src/reprieve/libs/ReprieveEvents.sol";

/**
 * @title RescueEscrowTest
 * @notice Slide 4 validation: Rescue Escrow (Failed Transfer Safety)
 */
contract RescueEscrowTest is Test {
    // Events for testing
    event EscrowCreated(bytes32 indexed escrowId, address indexed owner, address asset, uint256 amount, bytes32 relatedExecId);
    event EscrowClaimed(bytes32 indexed escrowId, address indexed claimer, uint256 amount);
    event EscrowRetried(bytes32 indexed escrowId, uint256 retryCount, bytes32 newExecId);
    
    RescueEscrow escrow;
    RescueLog rescueLog;
    MockERC20 token;
    
    address owner;
    address executor;
    address receiver;
    address user;
    address notAuthorized;
    address minter;
    
    bytes32 constant EXEC_ID = keccak256("test-exec-1");
    bytes32 constant ESCROW_ID = keccak256("test-escrow-1");
    
    function setUp() public {
        owner = address(this);
        executor = makeAddr("executor");
        receiver = makeAddr("receiver");
        user = makeAddr("user");
        notAuthorized = makeAddr("notAuthorized");
        minter = makeAddr("minter");
        
        // Deploy mock token
        token = new MockERC20("TEST", "TEST", 18, minter);
        
        // Deploy RescueLog
        rescueLog = new RescueLog(owner);
        
        // Deploy RescueEscrow
        escrow = new RescueEscrow(owner, address(rescueLog));
        
        // Authorize depositors
        escrow.setAuthorizedDepositor(executor, true);
        escrow.setAuthorizedDepositor(receiver, true);
        
        // Authorize writers for rescue log
        rescueLog.setAuthorizedWriter(address(escrow), true);
        rescueLog.setAuthorizedWriter(executor, true);
        
        // Mint tokens to executor for deposit
        vm.prank(minter);
        token.mint(executor, 10000 ether);
    }
    
    // ============ AUTHORIZATION TESTS ============
    
    function test_SetAuthorizedDepositor() public {
        address newDepositor = makeAddr("newDepositor");
        escrow.setAuthorizedDepositor(newDepositor, true);
        assertTrue(escrow.authorizedDepositors(newDepositor));
    }
    
    function test_SetAuthorizedDepositor_Revoke() public {
        escrow.setAuthorizedDepositor(executor, false);
        assertFalse(escrow.authorizedDepositors(executor));
    }
    
    function test_SetAuthorizedDepositor_OnlyOwner() public {
        vm.prank(notAuthorized);
        vm.expectRevert();
        escrow.setAuthorizedDepositor(notAuthorized, true);
    }
    
    function test_SetAuthorizedDepositor_ZeroAddressReverts() public {
        vm.expectRevert(ReprieveErrors.ZeroAddress.selector);
        escrow.setAuthorizedDepositor(address(0), true);
    }
    
    // ============ DEPOSIT TESTS ============
    
    function test_DepositFailedTransfer() public {
        uint256 amount = 1000 ether;
        
        vm.startPrank(executor);
        token.approve(address(escrow), amount);
        escrow.depositFailedTransfer(ESCROW_ID, user, address(token), amount, 421614, 84532, EXEC_ID);
        vm.stopPrank();
        
        ReprieveTypes.EscrowRecord memory record = escrow.getEscrow(ESCROW_ID);
        assertEq(record.owner, user);
        assertEq(record.asset, address(token));
        assertEq(record.amount, amount);
        assertEq(record.sourceChain, 421614);
        assertEq(record.targetChain, 84532);
        assertEq(uint256(record.status), uint256(ReprieveTypes.EscrowStatus.Pending));
        assertEq(record.retryCount, 0);
        assertEq(record.relatedExecId, EXEC_ID);
    }
    
    function test_DepositFailedTransfer_EmitsEvent() public {
        uint256 amount = 1000 ether;
        
        vm.startPrank(executor);
        token.approve(address(escrow), amount);
        
        vm.expectEmit(true, true, false, true);
        emit EscrowCreated(ESCROW_ID, user, address(token), amount, EXEC_ID);
        
        escrow.depositFailedTransfer(ESCROW_ID, user, address(token), amount, 421614, 84532, EXEC_ID);
        vm.stopPrank();
    }
    
    function test_DepositFailedTransfer_UnauthorizedReverts() public {
        vm.prank(notAuthorized);
        vm.expectRevert(abi.encodeWithSelector(ReprieveErrors.UnauthorizedWorkflow.selector, notAuthorized));
        escrow.depositFailedTransfer(ESCROW_ID, user, address(token), 1000, 421614, 84532, EXEC_ID);
    }
    
    function test_DepositFailedTransfer_DuplicateEscrowIdReverts() public {
        uint256 amount = 1000 ether;
        
        vm.startPrank(executor);
        token.approve(address(escrow), amount * 2);
        escrow.depositFailedTransfer(ESCROW_ID, user, address(token), amount, 421614, 84532, EXEC_ID);
        
        vm.expectRevert(abi.encodeWithSelector(ReprieveErrors.EscrowAlreadyClaimed.selector, ESCROW_ID));
        escrow.depositFailedTransfer(ESCROW_ID, user, address(token), amount, 421614, 84532, EXEC_ID);
        vm.stopPrank();
    }
    
    function test_DepositFailedTransfer_ZeroOwnerReverts() public {
        vm.prank(executor);
        vm.expectRevert(ReprieveErrors.ZeroAddress.selector);
        escrow.depositFailedTransfer(ESCROW_ID, address(0), address(token), 1000, 421614, 84532, EXEC_ID);
    }
    
    function test_DepositFailedTransfer_ZeroAssetReverts() public {
        vm.prank(executor);
        vm.expectRevert(ReprieveErrors.ZeroAddress.selector);
        escrow.depositFailedTransfer(ESCROW_ID, user, address(0), 1000, 421614, 84532, EXEC_ID);
    }
    
    function test_DepositFailedTransfer_ZeroAmountReverts() public {
        vm.prank(executor);
        vm.expectRevert(ReprieveErrors.ZeroAmount.selector);
        escrow.depositFailedTransfer(ESCROW_ID, user, address(token), 0, 421614, 84532, EXEC_ID);
    }
    
    // ============ CLAIM TESTS ============
    
    function test_ClaimEscrow() public {
        uint256 amount = 1000 ether;
        
        // Setup deposit
        vm.startPrank(executor);
        token.approve(address(escrow), amount);
        escrow.depositFailedTransfer(ESCROW_ID, user, address(token), amount, 421614, 84532, EXEC_ID);
        vm.stopPrank();
        
        // User claims
        uint256 balanceBefore = token.balanceOf(user);
        
        vm.prank(user);
        escrow.claimEscrow(ESCROW_ID);
        
        uint256 balanceAfter = token.balanceOf(user);
        assertEq(balanceAfter - balanceBefore, amount);
        
        ReprieveTypes.EscrowRecord memory record = escrow.getEscrow(ESCROW_ID);
        assertEq(uint256(record.status), uint256(ReprieveTypes.EscrowStatus.Claimed));
    }
    
    function test_ClaimEscrow_EmitsEvent() public {
        uint256 amount = 1000 ether;
        
        vm.startPrank(executor);
        token.approve(address(escrow), amount);
        escrow.depositFailedTransfer(ESCROW_ID, user, address(token), amount, 421614, 84532, EXEC_ID);
        vm.stopPrank();
        
        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit EscrowClaimed(ESCROW_ID, user, amount);
        escrow.claimEscrow(ESCROW_ID);
    }
    
    function test_ClaimEscrow_NotOwnerReverts() public {
        uint256 amount = 1000 ether;
        
        vm.startPrank(executor);
        token.approve(address(escrow), amount);
        escrow.depositFailedTransfer(ESCROW_ID, user, address(token), amount, 421614, 84532, EXEC_ID);
        vm.stopPrank();
        
        vm.prank(notAuthorized);
        vm.expectRevert(abi.encodeWithSelector(ReprieveErrors.EscrowNotClaimable.selector, ESCROW_ID));
        escrow.claimEscrow(ESCROW_ID);
    }
    
    function test_ClaimEscrow_AlreadyClaimedReverts() public {
        uint256 amount = 1000 ether;
        
        vm.startPrank(executor);
        token.approve(address(escrow), amount);
        escrow.depositFailedTransfer(ESCROW_ID, user, address(token), amount, 421614, 84532, EXEC_ID);
        vm.stopPrank();
        
        vm.prank(user);
        escrow.claimEscrow(ESCROW_ID);
        
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ReprieveErrors.EscrowNotClaimable.selector, ESCROW_ID));
        escrow.claimEscrow(ESCROW_ID);
    }
    
    function test_ClaimEscrow_ExpiredReverts() public {
        uint256 amount = 1000 ether;
        
        vm.startPrank(executor);
        token.approve(address(escrow), amount);
        escrow.depositFailedTransfer(ESCROW_ID, user, address(token), amount, 421614, 84532, EXEC_ID);
        vm.stopPrank();
        
        // Warp past timeout
        vm.warp(block.timestamp + escrow.ESCROW_TIMEOUT() + 1);
        
        // Expired escrows return EscrowNotClaimable because _canClaim returns false
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ReprieveErrors.EscrowNotClaimable.selector, ESCROW_ID));
        escrow.claimEscrow(ESCROW_ID);
    }
    
    // ============ RETRY TESTS ============
    
    function test_RetryTransfer() public {
        uint256 amount = 1000 ether;
        
        vm.startPrank(executor);
        token.approve(address(escrow), amount);
        escrow.depositFailedTransfer(ESCROW_ID, user, address(token), amount, 421614, 84532, EXEC_ID);
        
        uint256 executorBalanceBefore = token.balanceOf(executor);
        
        bytes memory retryData = abi.encode("retry params");
        escrow.retryTransfer(ESCROW_ID, retryData);
        
        uint256 executorBalanceAfter = token.balanceOf(executor);
        assertEq(executorBalanceAfter - executorBalanceBefore, amount);
        
        ReprieveTypes.EscrowRecord memory record = escrow.getEscrow(ESCROW_ID);
        assertEq(uint256(record.status), uint256(ReprieveTypes.EscrowStatus.Retried));
        assertEq(record.retryCount, 1);
        vm.stopPrank();
    }
    
    function test_RetryTransfer_EmitsEvent() public {
        uint256 amount = 1000 ether;
        
        vm.startPrank(executor);
        token.approve(address(escrow), amount);
        escrow.depositFailedTransfer(ESCROW_ID, user, address(token), amount, 421614, 84532, EXEC_ID);
        
        vm.expectEmit(true, false, false, true);
        emit EscrowRetried(ESCROW_ID, 1, EXEC_ID);
        
        bytes memory retryData = abi.encode("retry params");
        escrow.retryTransfer(ESCROW_ID, retryData);
        vm.stopPrank();
    }
    
    function test_RetryTransfer_SingleRetryPerEscrow() public {
        // Each escrow can only be retried once because status changes to Retried
        uint256 amount = 1000 ether;
        
        vm.startPrank(executor);
        token.approve(address(escrow), amount);
        escrow.depositFailedTransfer(ESCROW_ID, user, address(token), amount, 421614, 84532, EXEC_ID);
        
        // First retry - succeeds
        escrow.retryTransfer(ESCROW_ID, abi.encode("retry-1"));
        
        // Verify status is now Retried
        ReprieveTypes.EscrowRecord memory record = escrow.getEscrow(ESCROW_ID);
        assertEq(uint256(record.status), uint256(ReprieveTypes.EscrowStatus.Retried));
        assertEq(record.retryCount, 1);
        
        // Second retry on same escrow should fail because status is not Pending
        // The onlyPendingEscrow modifier reverts with EscrowNotClaimable
        vm.expectRevert(abi.encodeWithSelector(ReprieveErrors.EscrowNotClaimable.selector, ESCROW_ID));
        escrow.retryTransfer(ESCROW_ID, abi.encode("retry-2"));
        vm.stopPrank();
    }
    
    function test_RetryTransfer_UnauthorizedReverts() public {
        uint256 amount = 1000 ether;
        
        vm.startPrank(executor);
        token.approve(address(escrow), amount);
        escrow.depositFailedTransfer(ESCROW_ID, user, address(token), amount, 421614, 84532, EXEC_ID);
        vm.stopPrank();
        
        vm.prank(notAuthorized);
        vm.expectRevert(abi.encodeWithSelector(ReprieveErrors.UnauthorizedWorkflow.selector, notAuthorized));
        escrow.retryTransfer(ESCROW_ID, abi.encode("retry"));
    }
    
    // ============ CAN CLAIM TESTS ============
    
    function test_CanClaim() public {
        uint256 amount = 1000 ether;
        
        vm.startPrank(executor);
        token.approve(address(escrow), amount);
        escrow.depositFailedTransfer(ESCROW_ID, user, address(token), amount, 421614, 84532, EXEC_ID);
        vm.stopPrank();
        
        assertTrue(escrow.canClaim(ESCROW_ID, user));
        assertFalse(escrow.canClaim(ESCROW_ID, notAuthorized));
    }
    
    function test_CanClaim_Expired() public {
        uint256 amount = 1000 ether;
        
        vm.startPrank(executor);
        token.approve(address(escrow), amount);
        escrow.depositFailedTransfer(ESCROW_ID, user, address(token), amount, 421614, 84532, EXEC_ID);
        vm.stopPrank();
        
        assertFalse(escrow.isExpired(ESCROW_ID));
        
        vm.warp(block.timestamp + escrow.ESCROW_TIMEOUT() + 1);
        
        assertTrue(escrow.isExpired(ESCROW_ID));
        assertFalse(escrow.canClaim(ESCROW_ID, user));
    }
    
    // ============ USER ESCROWS TESTS ============
    
    function test_GetUserEscrows() public {
        uint256 amount = 1000 ether;
        
        vm.startPrank(executor);
        token.approve(address(escrow), amount * 3);
        
        bytes32 escrowId1 = keccak256("escrow-1");
        bytes32 escrowId2 = keccak256("escrow-2");
        bytes32 escrowId3 = keccak256("escrow-3");
        
        escrow.depositFailedTransfer(escrowId1, user, address(token), amount, 421614, 84532, EXEC_ID);
        escrow.depositFailedTransfer(escrowId2, user, address(token), amount, 421614, 84532, EXEC_ID);
        escrow.depositFailedTransfer(escrowId3, user, address(token), amount, 421614, 84532, EXEC_ID);
        vm.stopPrank();
        
        bytes32[] memory userEscrowIds = escrow.getUserEscrows(user);
        assertEq(userEscrowIds.length, 3);
        assertEq(userEscrowIds[0], escrowId1);
        assertEq(userEscrowIds[1], escrowId2);
        assertEq(userEscrowIds[2], escrowId3);
        
        assertEq(escrow.getUserEscrowCount(user), 3);
    }
    
    // ============ COMPLETE SCENARIO TESTS ============
    
    function test_Scenario_DepositClaim() public {
        // 1. Cross-chain transfer fails, funds deposited to escrow
        uint256 amount = 5000 ether;
        
        vm.startPrank(executor);
        token.approve(address(escrow), amount);
        escrow.depositFailedTransfer(ESCROW_ID, user, address(token), amount, 421614, 84532, EXEC_ID);
        vm.stopPrank();
        
        assertEq(token.balanceOf(address(escrow)), amount);
        
        // 2. User claims funds
        vm.prank(user);
        escrow.claimEscrow(ESCROW_ID);
        
        assertEq(token.balanceOf(user), amount);
        assertEq(token.balanceOf(address(escrow)), 0);
        
        ReprieveTypes.EscrowRecord memory record = escrow.getEscrow(ESCROW_ID);
        assertEq(uint256(record.status), uint256(ReprieveTypes.EscrowStatus.Claimed));
    }
    
    function test_Scenario_DepositRetry() public {
        // 1. Cross-chain transfer fails, funds deposited to escrow
        uint256 amount = 5000 ether;
        
        vm.startPrank(executor);
        token.approve(address(escrow), amount);
        escrow.depositFailedTransfer(ESCROW_ID, user, address(token), amount, 421614, 84532, EXEC_ID);
        
        // 2. Protocol retries (funds returned to executor)
        uint256 executorBalanceBefore = token.balanceOf(executor);
        escrow.retryTransfer(ESCROW_ID, abi.encode("retry-params"));
        uint256 executorBalanceAfter = token.balanceOf(executor);
        
        assertEq(executorBalanceAfter - executorBalanceBefore, amount);
        
        ReprieveTypes.EscrowRecord memory record = escrow.getEscrow(ESCROW_ID);
        assertEq(uint256(record.status), uint256(ReprieveTypes.EscrowStatus.Retried));
        assertEq(record.retryCount, 1);
        vm.stopPrank();
    }
    
    function test_Scenario_MultipleRetriesThenClaim() public {
        uint256 amount = 1000 ether;
        
        vm.startPrank(executor);
        
        // First attempt fails
        bytes32 escrowId1 = keccak256("escrow-retry-1");
        token.approve(address(escrow), amount * 3);
        escrow.depositFailedTransfer(escrowId1, user, address(token), amount, 421614, 84532, EXEC_ID);
        escrow.retryTransfer(escrowId1, abi.encode("retry-1"));
        
        // Second attempt fails
        bytes32 escrowId2 = keccak256("escrow-retry-2");
        escrow.depositFailedTransfer(escrowId2, user, address(token), amount, 421614, 84532, EXEC_ID);
        escrow.retryTransfer(escrowId2, abi.encode("retry-2"));
        
        // Third attempt - user claims instead of retry
        bytes32 escrowId3 = keccak256("escrow-retry-3");
        escrow.depositFailedTransfer(escrowId3, user, address(token), amount, 421614, 84532, EXEC_ID);
        vm.stopPrank();
        
        // User claims
        vm.prank(user);
        escrow.claimEscrow(escrowId3);
        
        assertEq(token.balanceOf(user), amount);
        
        // Verify all escrows
        assertEq(uint256(escrow.getEscrow(escrowId1).status), uint256(ReprieveTypes.EscrowStatus.Retried));
        assertEq(uint256(escrow.getEscrow(escrowId2).status), uint256(ReprieveTypes.EscrowStatus.Retried));
        assertEq(uint256(escrow.getEscrow(escrowId3).status), uint256(ReprieveTypes.EscrowStatus.Claimed));
    }
}
