// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockPriceOracle} from "../../src/mocks/MockPriceOracle.sol";
import {MockAavePool} from "../../src/mocks/MockAavePool.sol";
import {MockCompoundMarket} from "../../src/mocks/MockCompoundMarket.sol";
import {AaveLikeAdapter} from "../../src/adapters/AaveLikeAdapter.sol";
import {CompoundLikeAdapter} from "../../src/adapters/CompoundLikeAdapter.sol";
import {RescueExecutor} from "../../src/reprieve/RescueExecutor.sol";
import {RescueLog} from "../../src/reprieve/RescueLog.sol";
import {RescueEscrow} from "../../src/reprieve/RescueEscrow.sol";
import {AdapterRegistry} from "../../src/reprieve/AdapterRegistry.sol";
import {ReprieveWorkflowReceiver} from "../../src/reprieve/ReprieveWorkflowReceiver.sol";
import {WorkflowReceiverTemplate} from "../../src/reprieve/interfaces/WorkflowReceiverTemplate.sol";
import {ReprieveTypes} from "../../src/reprieve/libs/ReprieveTypes.sol";

contract ReprieveWorkflowReceiverTest is Test {
    MockERC20 collateral;
    MockERC20 debt;
    MockPriceOracle oracle;
    MockAavePool aavePool;
    MockCompoundMarket compoundMarket;
    AaveLikeAdapter aaveAdapter;
    CompoundLikeAdapter compoundAdapter;

    RescueExecutor executor;
    RescueLog rescueLog;
    RescueEscrow rescueEscrow;
    AdapterRegistry adapterRegistry;
    ReprieveWorkflowReceiver receiver;

    address owner;
    address user;
    address minter;
    address forwarder;
    address attacker;

    function setUp() public {
        owner = address(this);
        user = makeAddr("user");
        minter = makeAddr("minter");
        forwarder = makeAddr("forwarder");
        attacker = makeAddr("attacker");

        collateral = new MockERC20("WETH", "WETH", 18, minter);
        debt = new MockERC20("USDC", "USDC", 6, minter);

        oracle = new MockPriceOracle(owner, 30 minutes);
        oracle.setPrice(address(collateral), 2000e18);
        oracle.setPrice(address(debt), 1e18);

        aavePool = new MockAavePool(address(collateral), address(debt), address(oracle), owner);
        compoundMarket = new MockCompoundMarket(address(collateral), address(debt), address(oracle), owner);
        aavePool.engine().setAuthorizedOperator(address(aavePool), true);
        compoundMarket.engine().setAuthorizedOperator(address(compoundMarket), true);

        aaveAdapter = new AaveLikeAdapter(address(aavePool), address(collateral), address(debt), owner);
        compoundAdapter = new CompoundLikeAdapter(
            address(compoundMarket),
            address(collateral),
            address(debt),
            address(compoundMarket.cToken()),
            owner
        );

        rescueLog = new RescueLog(owner);
        rescueEscrow = new RescueEscrow(owner, address(rescueLog));
        adapterRegistry = new AdapterRegistry(owner);
        adapterRegistry.initializeDemoProtocols();
        adapterRegistry.setAdapter(adapterRegistry.AAVE_LIKE(), address(aaveAdapter));
        adapterRegistry.setAdapter(adapterRegistry.COMPOUND_LIKE(), address(compoundAdapter));

        executor = new RescueExecutor(owner, address(rescueLog), address(rescueEscrow), address(adapterRegistry));
        rescueLog.setAuthorizedWriter(address(executor), true);
        rescueEscrow.setAuthorizedDepositor(address(executor), true);

        receiver = new ReprieveWorkflowReceiver(owner, forwarder, address(executor));
        executor.setAuthorizedWorkflow(address(receiver), true);

        vm.startPrank(minter);
        debt.mint(address(aavePool.engine()), 1_000_000e6);
        debt.mint(address(compoundMarket.engine()), 1_000_000e6);
        collateral.mint(user, 100 ether);
        vm.stopPrank();
    }

    function test_OnReport_RevertsForNonForwarder() public {
        ReprieveTypes.RescuePlan memory plan = _emptyPlan();

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(WorkflowReceiverTemplate.InvalidSender.selector, attacker, forwarder)
        );
        receiver.onReport("", abi.encode(plan));
    }

    function test_OnReport_RevertsForMetadataAuthorMismatch() public {
        receiver.setExpectedAuthor(owner);

        ReprieveTypes.RescuePlan memory plan = _emptyPlan();
        bytes memory metadata = _metadata(keccak256("wf-id"), bytes10(0), attacker);

        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(WorkflowReceiverTemplate.InvalidAuthor.selector, attacker, owner)
        );
        receiver.onReport(metadata, abi.encode(plan));
    }

    function test_OnReport_ExecutesRescueAndMarksProcessed() public {
        _seedTopUpSourceAndTarget();

        bytes32 execId = keccak256("receiver-topup-success");
        ReprieveTypes.RescuePlan memory plan = _topUpPlan(execId, 2 ether);

        uint256 targetCollateralBefore = compoundMarket.getUserPosition(user).collateral;

        vm.prank(forwarder);
        receiver.onReport("", abi.encode(plan));

        assertTrue(receiver.processedExecIds(execId));
        assertEq(
            compoundMarket.getUserPosition(user).collateral,
            targetCollateralBefore + 2 ether,
            "target collateral should increase"
        );
    }

    function test_OnReport_RevertsOnDuplicateExecId() public {
        _seedTopUpSourceAndTarget();

        bytes32 execId = keccak256("receiver-duplicate");
        ReprieveTypes.RescuePlan memory plan = _topUpPlan(execId, 1 ether);
        bytes memory report = abi.encode(plan);

        vm.prank(forwarder);
        receiver.onReport("", report);

        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(ReprieveWorkflowReceiver.DuplicateExecution.selector, execId)
        );
        receiver.onReport("", report);
    }

    function test_OnReport_RevertsWhenExecutorReturnsFalse() public {
        // Only source position is seeded; target step will fail and executor returns false.
        vm.startPrank(user);
        collateral.approve(address(aavePool), type(uint256).max);
        aavePool.supply(address(collateral), 8 ether, user, 0);
        vm.stopPrank();

        bytes32 execId = keccak256("receiver-plan-fails");
        ReprieveTypes.RescuePlan memory plan = _topUpPlan(execId, 2 ether);

        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(ReprieveWorkflowReceiver.RescueExecutionFailed.selector, execId)
        );
        receiver.onReport("", abi.encode(plan));

        assertFalse(receiver.processedExecIds(execId));
    }

    function _seedTopUpSourceAndTarget() internal {
        vm.startPrank(user);
        collateral.approve(address(aavePool), type(uint256).max);
        aavePool.supply(address(collateral), 10 ether, user, 0);
        aavePool.aToken().approve(address(aaveAdapter), type(uint256).max);

        collateral.approve(address(compoundMarket), type(uint256).max);
        compoundMarket.mint(address(collateral), 8 ether);
        compoundMarket.borrow(address(debt), 5000e6);
        vm.stopPrank();
    }

    function _topUpPlan(bytes32 execId, uint256 collateralAmount)
        internal
        view
        returns (ReprieveTypes.RescuePlan memory)
    {
        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](1);
        steps[0] = ReprieveTypes.RescueStep({
            stepIndex: 0,
            sourceAdapter: address(aaveAdapter),
            targetAdapter: address(compoundAdapter),
            collateralAsset: address(collateral),
            debtAsset: address(debt),
            collateralAmount: collateralAmount,
            debtAmount: 0,
            isCrossChain: false,
            targetChain: 0
        });

        return ReprieveTypes.RescuePlan({
            execId: execId,
            user: user,
            mode: ReprieveTypes.RescueMode.TOP_UP,
            steps: steps,
            deadline: block.timestamp + 1 hours,
            maxFee: 1 ether
        });
    }

    function _emptyPlan() internal view returns (ReprieveTypes.RescuePlan memory) {
        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](0);
        return ReprieveTypes.RescuePlan({
            execId: bytes32(0),
            user: address(0),
            mode: ReprieveTypes.RescueMode.TOP_UP,
            steps: steps,
            deadline: block.timestamp + 1 hours,
            maxFee: 0
        });
    }

    function _metadata(bytes32 workflowId, bytes10 workflowName, address workflowOwner)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(workflowId, workflowName, workflowOwner);
    }
}
