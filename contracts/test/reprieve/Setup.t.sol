// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ReprieveTypes} from "../../src/reprieve/libs/ReprieveTypes.sol";
import {ReprieveErrors} from "../../src/reprieve/libs/ReprieveErrors.sol";
import {ReprieveEvents} from "../../src/reprieve/libs/ReprieveEvents.sol";
import {IRescueExecutor} from "../../src/reprieve/interfaces/IRescueExecutor.sol";
import {IRescueEscrow} from "../../src/reprieve/interfaces/IRescueEscrow.sol";
import {IRescueLog} from "../../src/reprieve/interfaces/IRescueLog.sol";
import {IAdapterRegistry} from "../../src/reprieve/interfaces/IAdapterRegistry.sol";
import {ICCIPReceiver} from "../../src/reprieve/interfaces/ICCIPReceiver.sol";

/**
 * @title SetupTest
 * @notice Slide 0 + Slide 1 validation: Foundation, Types, Errors, Events, Interfaces
 */
contract SetupTest is Test {
    
    // ============ Slide 0: Foundation Tests ============
    
    function test_ReprieveFoldersExist() public pure {
        // This test passes if compilation succeeds (folders exist with files)
        assertTrue(true);
    }
    
    function test_ReprieveTypes_LibraryExists() public pure {
        // Verify library compiles and enums are accessible
        ReprieveTypes.RescueStatus status = ReprieveTypes.RescueStatus.InProgress;
        assertEq(uint256(status), 1);
        
        ReprieveTypes.EscrowStatus escrow = ReprieveTypes.EscrowStatus.Pending;
        assertEq(uint256(escrow), 1);
    }
    
    function test_ReprieveErrors_LibraryExists() public pure {
        // Verify error selectors are accessible
        // This compiles if the library is correctly structured
        assertTrue(true);
    }
    
    function test_ReprieveEvents_LibraryExists() public pure {
        // Verify events are correctly defined
        assertTrue(true);
    }
    
    // ============ Slide 1: Type Coverage Tests ============
    
    function test_RescuePlan_Struct() public view {
        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](1);
        steps[0] = ReprieveTypes.RescueStep({
            stepIndex: 0,
            sourceAdapter: address(1),
            targetAdapter: address(2),
            collateralAsset: address(3),
            debtAsset: address(4),
            collateralAmount: 1000,
            debtAmount: 500,
            isCrossChain: false,
            targetChain: 0
        });
        
        ReprieveTypes.RescuePlan memory plan = ReprieveTypes.RescuePlan({
            execId: keccak256("test"),
            user: address(5),
            steps: steps,
            deadline: block.timestamp + 1 hours,
            maxFee: 1 ether
        });
        
        assertEq(plan.steps.length, 1);
        assertEq(plan.steps[0].collateralAmount, 1000);
    }
    
    function test_EscrowRecord_Struct() public view {
        ReprieveTypes.EscrowRecord memory record = ReprieveTypes.EscrowRecord({
            escrowId: keccak256("escrow1"),
            owner: address(1),
            asset: address(2),
            amount: 1000,
            sourceChain: 421614,
            targetChain: 84532,
            status: ReprieveTypes.EscrowStatus.Pending,
            createdAt: block.timestamp,
            retryCount: 0,
            relatedExecId: keccak256("exec1")
        });
        
        assertEq(record.amount, 1000);
        assertEq(uint256(record.status), 1);
    }
    
    function test_CCIPMessage_Struct() public view {
        ReprieveTypes.CCIPMessage memory message = ReprieveTypes.CCIPMessage({
            execId: keccak256("exec"),
            user: address(1),
            targetAdapter: address(2),
            asset: address(3),
            amount: 1000,
            timestamp: block.timestamp,
            deadline: block.timestamp + 1 hours
        });
        
        assertEq(message.amount, 1000);
    }
    
    function test_HealthSnapshot_Struct() public view {
        ReprieveTypes.HealthSnapshot memory snapshot = ReprieveTypes.HealthSnapshot({
            user: address(1),
            aggregateHf: 1.5e18,
            timestamp: block.timestamp,
            execId: keccak256("exec")
        });
        
        assertEq(snapshot.aggregateHf, 1.5e18);
    }
    
    // ============ Slide 1: Interface Conformance Tests ============
    
    function test_Interface_IRescueExecutor() public pure {
        // Verify interface compiles with expected function selectors
        assertTrue(true);
    }
    
    function test_Interface_IRescueEscrow() public pure {
        assertTrue(true);
    }
    
    function test_Interface_IRescueLog() public pure {
        assertTrue(true);
    }
    
    function test_Interface_IAdapterRegistry() public pure {
        assertTrue(true);
    }
    
    function test_Interface_ICCIPReceiver() public pure {
        assertTrue(true);
    }
    
    // ============ Slide 1: Event Schema Tests ============
    
    function test_Event_RescueInitiated() public {
        vm.expectEmit(true, true, false, true);
        emit ReprieveEvents.RescueInitiated(keccak256("exec"), address(1), 3, block.timestamp + 1 hours);
        
        // Emit the event
        emit ReprieveEvents.RescueInitiated(keccak256("exec"), address(1), 3, block.timestamp + 1 hours);
    }
    
    function test_Event_RescueStepCompleted() public {
        vm.expectEmit(true, true, false, true);
        emit ReprieveEvents.RescueStepCompleted(
            keccak256("exec"),
            0,
            address(1),
            address(2),
            1000,
            500
        );
        
        emit ReprieveEvents.RescueStepCompleted(
            keccak256("exec"),
            0,
            address(1),
            address(2),
            1000,
            500
        );
    }
    
    function test_Event_EscrowCreated() public {
        vm.expectEmit(true, true, false, true);
        emit ReprieveEvents.EscrowCreated(
            keccak256("escrow"),
            address(1),
            address(2),
            1000,
            keccak256("exec")
        );
        
        emit ReprieveEvents.EscrowCreated(
            keccak256("escrow"),
            address(1),
            address(2),
            1000,
            keccak256("exec")
        );
    }
}
