// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {HealthMonitor} from "../../src/reprieve/HealthMonitor.sol";
import {ReprieveTypes} from "../../src/reprieve/libs/ReprieveTypes.sol";
import {ReprieveEvents} from "../../src/reprieve/libs/ReprieveEvents.sol";
import {ReprieveErrors} from "../../src/reprieve/libs/ReprieveErrors.sol";

contract HealthMonitorTest is Test {
    HealthMonitor internal monitor;

    address internal owner;
    address internal reporter;
    address internal user;
    address internal unauthorized;

    function setUp() public {
        owner = makeAddr("owner");
        reporter = makeAddr("reporter");
        user = makeAddr("user");
        unauthorized = makeAddr("unauthorized");

        vm.prank(owner);
        monitor = new HealthMonitor(owner);
    }

    function test_SetAuthorizedReporter() public {
        vm.prank(owner);
        monitor.setAuthorizedReporter(reporter, true);

        assertTrue(monitor.authorizedReporters(reporter));
    }

    function test_SetAuthorizedReporter_OnlyOwner() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        monitor.setAuthorizedReporter(reporter, true);
    }

    function test_SetAuthorizedReporter_ZeroAddressReverts() public {
        vm.prank(owner);
        vm.expectRevert(ReprieveErrors.ZeroAddress.selector);
        monitor.setAuthorizedReporter(address(0), true);
    }

    function test_SetAuthorizedReporter_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit ReprieveEvents.ReporterAuthorized(reporter, true);

        vm.prank(owner);
        monitor.setAuthorizedReporter(reporter, true);
    }

    function test_RecordHealthSnapshot() public {
        vm.prank(owner);
        monitor.setAuthorizedReporter(reporter, true);

        bytes32 execId = keccak256("exec-1");
        uint256 hf = 1.35e18;
        uint256 timestamp = block.timestamp;

        vm.prank(reporter);
        monitor.recordHealthSnapshot(user, hf, timestamp, execId);

        ReprieveTypes.HealthSnapshot memory latest = monitor.getLatestSnapshot(user);
        assertEq(latest.user, user);
        assertEq(latest.aggregateHf, hf);
        assertEq(latest.timestamp, timestamp);
        assertEq(latest.execId, execId);
    }

    function test_RecordHealthSnapshot_UsesBlockTimestampWhenZero() public {
        vm.prank(owner);
        monitor.setAuthorizedReporter(reporter, true);

        bytes32 execId = keccak256("exec-2");
        uint256 hf = 1.4e18;

        vm.warp(123456);
        vm.prank(reporter);
        monitor.recordHealthSnapshot(user, hf, 0, execId);

        ReprieveTypes.HealthSnapshot memory latest = monitor.getLatestSnapshot(user);
        assertEq(latest.timestamp, 123456);
    }

    function test_RecordHealthSnapshot_UnauthorizedReverts() public {
        vm.expectRevert(abi.encodeWithSelector(ReprieveErrors.UnauthorizedWorkflow.selector, unauthorized));
        vm.prank(unauthorized);
        monitor.recordHealthSnapshot(user, 1.3e18, block.timestamp, keccak256("exec"));
    }

    function test_RecordHealthSnapshot_ZeroUserReverts() public {
        vm.prank(owner);
        monitor.setAuthorizedReporter(reporter, true);

        vm.expectRevert(ReprieveErrors.ZeroAddress.selector);
        vm.prank(reporter);
        monitor.recordHealthSnapshot(address(0), 1.3e18, block.timestamp, keccak256("exec"));
    }

    function test_RecordHealthSnapshot_ZeroHfReverts() public {
        vm.prank(owner);
        monitor.setAuthorizedReporter(reporter, true);

        vm.expectRevert(ReprieveErrors.ZeroAmount.selector);
        vm.prank(reporter);
        monitor.recordHealthSnapshot(user, 0, block.timestamp, keccak256("exec"));
    }

    function test_RecordHealthSnapshot_EmitsEvent() public {
        vm.prank(owner);
        monitor.setAuthorizedReporter(reporter, true);

        bytes32 execId = keccak256("exec-event");
        uint256 hf = 1.31e18;
        uint256 timestamp = block.timestamp;

        vm.expectEmit(true, true, true, true);
        emit ReprieveEvents.HealthSnapshotRecorded(user, hf, timestamp, execId, reporter);

        vm.prank(reporter);
        monitor.recordHealthSnapshot(user, hf, timestamp, execId);
    }

    function test_GetSnapshotCount_And_GetSnapshotAt() public {
        vm.prank(owner);
        monitor.setAuthorizedReporter(reporter, true);

        vm.prank(reporter);
        monitor.recordHealthSnapshot(user, 1.4e18, block.timestamp, keccak256("a"));
        vm.prank(reporter);
        monitor.recordHealthSnapshot(user, 1.3e18, block.timestamp + 1, keccak256("b"));

        assertEq(monitor.getSnapshotCount(user), 2);
        ReprieveTypes.HealthSnapshot memory first = monitor.getSnapshotAt(user, 0);
        ReprieveTypes.HealthSnapshot memory second = monitor.getSnapshotAt(user, 1);
        assertEq(first.aggregateHf, 1.4e18);
        assertEq(second.aggregateHf, 1.3e18);
    }

    function test_GetSnapshotAt_IndexOutOfBoundsReverts() public {
        vm.expectRevert(abi.encodeWithSelector(ReprieveErrors.InvalidStepIndex.selector, 0));
        monitor.getSnapshotAt(user, 0);
    }

    function test_GetLatestSnapshot_NoSnapshotsReverts() public {
        vm.expectRevert(abi.encodeWithSelector(ReprieveErrors.InvalidRescuePlan.selector, "No snapshots"));
        monitor.getLatestSnapshot(user);
    }

    function test_EmitUrgentRescue() public {
        vm.prank(owner);
        monitor.setAuthorizedReporter(reporter, true);

        uint256 prevHf = 1.5e18;
        uint256 newHf = 1.2e18; // 20% drop
        uint256 expectedDropBps = 2000;

        vm.expectEmit(true, true, false, true);
        emit ReprieveEvents.UrgentRescue(user, prevHf, newHf, expectedDropBps, reporter);

        vm.prank(reporter);
        monitor.emitUrgentRescue(user, prevHf, newHf);
    }

    function test_EmitUrgentRescue_UnauthorizedReverts() public {
        vm.expectRevert(abi.encodeWithSelector(ReprieveErrors.UnauthorizedWorkflow.selector, unauthorized));
        vm.prank(unauthorized);
        monitor.emitUrgentRescue(user, 1.4e18, 1.2e18);
    }

    function test_EmitUrgentRescue_InvalidDirectionReverts() public {
        vm.prank(owner);
        monitor.setAuthorizedReporter(reporter, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                ReprieveErrors.InvalidRescuePlan.selector,
                "newHf must be lower than prevHf"
            )
        );
        vm.prank(reporter);
        monitor.emitUrgentRescue(user, 1.2e18, 1.3e18);
    }

    function test_EmitUrgentRescue_ZeroValuesRevert() public {
        vm.prank(owner);
        monitor.setAuthorizedReporter(reporter, true);

        vm.expectRevert(ReprieveErrors.ZeroAmount.selector);
        vm.prank(reporter);
        monitor.emitUrgentRescue(user, 0, 1.2e18);
    }
}
