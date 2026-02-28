// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {RescueLog} from "../../src/reprieve/RescueLog.sol";
import {ReprieveTypes} from "../../src/reprieve/libs/ReprieveTypes.sol";
import {ReprieveErrors} from "../../src/reprieve/libs/ReprieveErrors.sol";
import {ReprieveEvents} from "../../src/reprieve/libs/ReprieveEvents.sol";
import {IRescueLog} from "../../src/reprieve/interfaces/IRescueLog.sol";

/**
 * @title RescueLogTest
 * @notice Slide 3 validation: Rescue Log (Immutable Audit Trail)
 */
contract RescueLogTest is Test {
    // Events for testing
    event LogEntryAdded(bytes32 indexed execId, uint256 indexed stepIndex, address indexed user, ReprieveTypes.RescueStatus status, string details);
    event RescueInitiated(bytes32 indexed execId, address indexed user, uint256 steps, uint256 deadline);
    event RescueCompleted(bytes32 indexed execId, address indexed user, ReprieveTypes.RescueStatus status, uint256 finalStepIndex);
    event RescueFailed(bytes32 indexed execId, address indexed user, string reason, uint256 failedStepIndex);
    event WriterAuthorized(address indexed writer, bool allowed);
    
    RescueLog rescueLog;
    address owner;
    address executor;
    address receiver;
    address escrow;
    address notAuthorized;
    address user;
    
    bytes32 constant EXEC_ID = keccak256("test-exec-1");
    
    function setUp() public {
        owner = address(this);
        executor = makeAddr("executor");
        receiver = makeAddr("receiver");
        escrow = makeAddr("escrow");
        notAuthorized = makeAddr("notAuthorized");
        user = makeAddr("user");
        
        rescueLog = new RescueLog(owner);
        
        // Authorize writers
        rescueLog.setAuthorizedWriter(executor, true);
        rescueLog.setAuthorizedWriter(receiver, true);
        rescueLog.setAuthorizedWriter(escrow, true);
    }
    
    // ============ AUTHORIZATION TESTS ============
    
    function test_SetAuthorizedWriter() public {
        address newWriter = makeAddr("newWriter");
        
        vm.expectEmit(true, false, false, true);
        emit WriterAuthorized(newWriter, true);
        
        rescueLog.setAuthorizedWriter(newWriter, true);
        assertTrue(rescueLog.isAuthorizedWriter(newWriter));
    }
    
    function test_SetAuthorizedWriter_Revoke() public {
        rescueLog.setAuthorizedWriter(executor, false);
        assertFalse(rescueLog.isAuthorizedWriter(executor));
    }
    
    function test_SetAuthorizedWriter_OnlyOwner() public {
        vm.prank(notAuthorized);
        vm.expectRevert();
        rescueLog.setAuthorizedWriter(notAuthorized, true);
    }
    
    function test_SetAuthorizedWriter_ZeroAddressReverts() public {
        vm.expectRevert(ReprieveErrors.ZeroAddress.selector);
        rescueLog.setAuthorizedWriter(address(0), true);
    }
    
    // ============ LOG RESCUE INITIATED TESTS ============
    
    function test_LogRescueInitiated() public {
        vm.prank(executor);
        rescueLog.logRescueInitiated(EXEC_ID, user, 3);
        
        assertTrue(rescueLog.hasEntries(EXEC_ID));
        assertEq(rescueLog.getLogEntryCount(EXEC_ID), 1);
        assertEq(rescueLog.totalEntries(), 1);
        
        ReprieveTypes.LogEntry[] memory entries = rescueLog.getLogEntries(EXEC_ID);
        assertEq(entries[0].execId, EXEC_ID);
        assertEq(entries[0].stepIndex, 0);
        assertEq(entries[0].user, user);
        assertEq(uint256(entries[0].status), uint256(ReprieveTypes.RescueStatus.InProgress));
    }
    
    function test_LogRescueInitiated_EmitsEvents() public {
        vm.prank(executor);
        
        vm.expectEmit(true, true, false, true);
        emit RescueInitiated(EXEC_ID, user, 3, block.timestamp + 1 hours);
        
        rescueLog.logRescueInitiated(EXEC_ID, user, 3);
    }
    
    function test_LogRescueInitiated_UnauthorizedReverts() public {
        vm.prank(notAuthorized);
        vm.expectRevert(abi.encodeWithSelector(ReprieveErrors.UnauthorizedWorkflow.selector, notAuthorized));
        rescueLog.logRescueInitiated(EXEC_ID, user, 3);
    }
    
    function test_LogRescueInitiated_DuplicateExecIdReverts() public {
        vm.startPrank(executor);
        rescueLog.logRescueInitiated(EXEC_ID, user, 3);
        
        vm.expectRevert(abi.encodeWithSelector(ReprieveErrors.RescueAlreadyInProgress.selector, user));
        rescueLog.logRescueInitiated(EXEC_ID, user, 3);
        vm.stopPrank();
    }
    
    // ============ LOG RESCUE STEP TESTS ============
    
    function test_LogRescueStep() public {
        vm.startPrank(executor);
        rescueLog.logRescueInitiated(EXEC_ID, user, 3);
        rescueLog.logRescueStep(EXEC_ID, 1, user, "Withdrew 1000 collateral");
        vm.stopPrank();
        
        assertEq(rescueLog.getLogEntryCount(EXEC_ID), 2);
        
        ReprieveTypes.LogEntry[] memory entries = rescueLog.getLogEntries(EXEC_ID);
        assertEq(entries[1].stepIndex, 1);
        assertEq(entries[1].details, "Withdrew 1000 collateral");
    }
    
    function test_LogRescueStep_MultipleSteps() public {
        vm.startPrank(executor);
        rescueLog.logRescueInitiated(EXEC_ID, user, 3);
        rescueLog.logRescueStep(EXEC_ID, 1, user, "Step 1 complete");
        rescueLog.logRescueStep(EXEC_ID, 2, user, "Step 2 complete");
        rescueLog.logRescueStep(EXEC_ID, 3, user, "Step 3 complete");
        vm.stopPrank();
        
        assertEq(rescueLog.getLogEntryCount(EXEC_ID), 4);
    }
    
    function test_LogRescueStep_InvalidExecIdReverts() public {
        bytes32 invalidExecId = keccak256("invalid");
        
        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(ReprieveErrors.InvalidRescuePlan.selector, "ExecId not found"));
        rescueLog.logRescueStep(invalidExecId, 1, user, "Test");
    }
    
    function test_LogRescueStep_UnauthorizedReverts() public {
        vm.prank(executor);
        rescueLog.logRescueInitiated(EXEC_ID, user, 3);
        
        vm.prank(notAuthorized);
        vm.expectRevert(abi.encodeWithSelector(ReprieveErrors.UnauthorizedWorkflow.selector, notAuthorized));
        rescueLog.logRescueStep(EXEC_ID, 1, user, "Test");
    }
    
    // ============ LOG RESCUE COMPLETED TESTS ============
    
    function test_LogRescueCompleted() public {
        vm.startPrank(executor);
        rescueLog.logRescueInitiated(EXEC_ID, user, 3);
        rescueLog.logRescueCompleted(EXEC_ID, user, ReprieveTypes.RescueStatus.Completed, "All steps completed");
        vm.stopPrank();
        
        ReprieveTypes.LogEntry[] memory entries = rescueLog.getLogEntries(EXEC_ID);
        assertEq(uint256(entries[1].status), uint256(ReprieveTypes.RescueStatus.Completed));
        assertEq(entries[1].details, "All steps completed");
    }
    
    function test_LogRescueCompleted_EmitsEvents() public {
        vm.startPrank(executor);
        rescueLog.logRescueInitiated(EXEC_ID, user, 3);
        
        vm.expectEmit(true, true, false, true);
        emit RescueCompleted(EXEC_ID, user, ReprieveTypes.RescueStatus.Completed, 1);
        
        rescueLog.logRescueCompleted(EXEC_ID, user, ReprieveTypes.RescueStatus.Completed, "Done");
        vm.stopPrank();
    }
    
    function test_LogRescueCompleted_PartialStatus() public {
        vm.startPrank(executor);
        rescueLog.logRescueInitiated(EXEC_ID, user, 3);
        rescueLog.logRescueCompleted(EXEC_ID, user, ReprieveTypes.RescueStatus.Partial, "Partial completion");
        vm.stopPrank();
        
        ReprieveTypes.LogEntry[] memory entries = rescueLog.getLogEntries(EXEC_ID);
        assertEq(uint256(entries[1].status), uint256(ReprieveTypes.RescueStatus.Partial));
    }
    
    function test_LogRescueCompleted_InvalidExecIdReverts() public {
        bytes32 invalidExecId = keccak256("invalid");
        
        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(ReprieveErrors.InvalidRescuePlan.selector, "ExecId not found"));
        rescueLog.logRescueCompleted(invalidExecId, user, ReprieveTypes.RescueStatus.Completed, "Test");
    }
    
    // ============ LOG RESCUE FAILED TESTS ============
    
    function test_LogRescueFailed() public {
        vm.startPrank(executor);
        rescueLog.logRescueInitiated(EXEC_ID, user, 3);
        rescueLog.logRescueFailed(EXEC_ID, user, "Insufficient collateral");
        vm.stopPrank();
        
        ReprieveTypes.LogEntry[] memory entries = rescueLog.getLogEntries(EXEC_ID);
        assertEq(uint256(entries[1].status), uint256(ReprieveTypes.RescueStatus.Failed));
        assertEq(entries[1].details, "Insufficient collateral");
    }
    
    function test_LogRescueFailed_EmitsEvents() public {
        vm.startPrank(executor);
        rescueLog.logRescueInitiated(EXEC_ID, user, 3);
        
        vm.expectEmit(true, true, false, true);
        emit RescueFailed(EXEC_ID, user, "Failed", 1);
        
        rescueLog.logRescueFailed(EXEC_ID, user, "Failed");
        vm.stopPrank();
    }
    
    // ============ COMPLETE SCENARIO TESTS ============
    
    function test_CompleteScenario_Success() public {
        vm.startPrank(executor);
        
        // Initiate
        rescueLog.logRescueInitiated(EXEC_ID, user, 3);
        
        // Steps
        rescueLog.logRescueStep(EXEC_ID, 1, user, "Source AAVE: withdrew 5 WETH");
        rescueLog.logRescueStep(EXEC_ID, 2, user, "Target COMPOUND: repaid 5000 USDC");
        rescueLog.logRescueStep(EXEC_ID, 3, user, "HF improved from 1.05 to 1.25");
        
        // Complete
        rescueLog.logRescueCompleted(EXEC_ID, user, ReprieveTypes.RescueStatus.Completed, "Rescue successful");
        
        vm.stopPrank();
        
        // Verify
        assertEq(rescueLog.getLogEntryCount(EXEC_ID), 5);
        assertEq(rescueLog.totalEntries(), 5);
        
        ReprieveTypes.LogEntry[] memory entries = rescueLog.getLogEntries(EXEC_ID);
        assertEq(entries[0].stepIndex, 0);
        assertEq(entries[1].stepIndex, 1);
        assertEq(entries[2].stepIndex, 2);
        assertEq(entries[3].stepIndex, 3);
        assertEq(entries[4].stepIndex, 4);
        
        // Verify status progression
        assertEq(uint256(entries[0].status), uint256(ReprieveTypes.RescueStatus.InProgress));
        assertEq(uint256(entries[4].status), uint256(ReprieveTypes.RescueStatus.Completed));
    }
    
    function test_CompleteScenario_Failure() public {
        vm.startPrank(executor);
        
        // Initiate
        rescueLog.logRescueInitiated(EXEC_ID, user, 2);
        
        // Step
        rescueLog.logRescueStep(EXEC_ID, 1, user, "Source AAVE: withdrew 2 WETH");
        
        // Fail
        rescueLog.logRescueFailed(EXEC_ID, user, "Target repay reverted: insufficient allowance");
        
        vm.stopPrank();
        
        assertEq(rescueLog.getLogEntryCount(EXEC_ID), 3);
        
        ReprieveTypes.LogEntry[] memory entries = rescueLog.getLogEntries(EXEC_ID);
        assertEq(uint256(entries[2].status), uint256(ReprieveTypes.RescueStatus.Failed));
    }
    
    function test_CompleteScenario_MultiSourceFallback() public {
        vm.startPrank(executor);
        
        // Initiate rescue from 3 sources
        bytes32 execId = keccak256("multi-source-exec");
        rescueLog.logRescueInitiated(execId, user, 3);
        
        // Try source 1
        rescueLog.logRescueStep(execId, 1, user, "Source 1 (AAVE): attempted withdraw");
        rescueLog.logRescueStep(execId, 1, user, "Source 1: insufficient available collateral");
        
        // Fall through to source 2
        rescueLog.logRescueStep(execId, 2, user, "Source 2 (Compound): withdrew 3 WETH");
        rescueLog.logRescueStep(execId, 2, user, "Target: repaid 3000 USDC");
        
        // Complete
        rescueLog.logRescueCompleted(execId, user, ReprieveTypes.RescueStatus.Completed, "Rescue via fallback source");
        
        vm.stopPrank();
        
        assertEq(rescueLog.getLogEntryCount(execId), 6);
    }
    
    // ============ GET LOG ENTRY TESTS ============
    
    function test_GetLogEntry() public {
        vm.startPrank(executor);
        rescueLog.logRescueInitiated(EXEC_ID, user, 1);
        vm.stopPrank();
        
        ReprieveTypes.LogEntry memory entry = rescueLog.getLogEntry(EXEC_ID, 0);
        assertEq(entry.execId, EXEC_ID);
        assertEq(entry.user, user);
    }
    
    function test_GetLogEntry_IndexOutOfBounds() public {
        vm.expectRevert("Index out of bounds");
        rescueLog.getLogEntry(EXEC_ID, 0);
    }
    
    // ============ CROSS-WRITER TESTS ============
    
    function test_MultipleWriters_CanLog() public {
        // Executor initiates
        vm.prank(executor);
        rescueLog.logRescueInitiated(EXEC_ID, user, 2);
        
        // Receiver logs step
        vm.prank(receiver);
        rescueLog.logRescueStep(EXEC_ID, 1, user, "CCIP message received");
        
        // Escrow logs failure
        vm.prank(escrow);
        rescueLog.logRescueFailed(EXEC_ID, user, "Funds moved to escrow");
        
        assertEq(rescueLog.getLogEntryCount(EXEC_ID), 3);
    }
}
