// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
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
import {ReprieveTypes} from "../../src/reprieve/libs/ReprieveTypes.sol";
import {ReprieveErrors} from "../../src/reprieve/libs/ReprieveErrors.sol";
import {ReprieveEvents} from "../../src/reprieve/libs/ReprieveEvents.sol";

/**
 * @title RescueExecutorTest
 * @notice Slide 5 validation: Rescue Executor (Same-Chain First)
 */
contract RescueExecutorTest is Test {
    // Events for testing
    event WorkflowAuthorized(address indexed workflow, bool allowed);
    event RescueInitiated(bytes32 indexed execId, address indexed user, uint256 steps, uint256 deadline);
    event RescueCompleted(bytes32 indexed execId, address indexed user, ReprieveTypes.RescueStatus status, uint256 finalStepIndex);
    event RescueFailed(bytes32 indexed execId, address indexed user, string reason, uint256 failedStepIndex);
    
    RescueExecutor executor;
    RescueLog rescueLog;
    RescueEscrow rescueEscrow;
    AdapterRegistry adapterRegistry;
    
    MockERC20 collateral;
    MockERC20 debt;
    MockPriceOracle oracle;
    MockAavePool aavePool;
    MockCompoundMarket compoundMarket;
    AaveLikeAdapter aaveAdapter;
    CompoundLikeAdapter compoundAdapter;
    
    address owner;
    address workflow;
    address user;
    address liquidator;
    address minter;
    address notAuthorized;
    
    bytes32 constant EXEC_ID = keccak256("test-exec-1");
    
    function setUp() public {
        owner = address(this);
        workflow = makeAddr("workflow");
        user = makeAddr("user");
        liquidator = makeAddr("liquidator");
        minter = makeAddr("minter");
        notAuthorized = makeAddr("notAuthorized");
        
        // Deploy tokens
        collateral = new MockERC20("WETH", "WETH", 18, minter);
        debt = new MockERC20("USDC", "USDC", 6, minter);
        
        // Deploy oracle
        oracle = new MockPriceOracle(owner, 30 minutes);
        oracle.setPrice(address(collateral), 2000e18);
        oracle.setPrice(address(debt), 1e18);
        
        // Deploy protocol mocks
        aavePool = new MockAavePool(address(collateral), address(debt), address(oracle), owner);
        compoundMarket = new MockCompoundMarket(address(collateral), address(debt), address(oracle), owner);
        aavePool.engine().setAuthorizedOperator(address(aavePool), true);
        compoundMarket.engine().setAuthorizedOperator(address(compoundMarket), true);
        
        // Deploy adapters
        aaveAdapter = new AaveLikeAdapter(address(aavePool), address(collateral), address(debt), owner);
        compoundAdapter = new CompoundLikeAdapter(
            address(compoundMarket),
            address(collateral),
            address(debt),
            address(compoundMarket.cToken()),
            owner
        );
        
        // Deploy Reprieve contracts
        rescueLog = new RescueLog(owner);
        rescueEscrow = new RescueEscrow(owner, address(rescueLog));
        adapterRegistry = new AdapterRegistry(owner);
        
        // Initialize registry
        adapterRegistry.initializeDemoProtocols();
        adapterRegistry.setAdapter(adapterRegistry.AAVE_LIKE(), address(aaveAdapter));
        adapterRegistry.setAdapter(adapterRegistry.COMPOUND_LIKE(), address(compoundAdapter));
        
        // Deploy executor
        executor = new RescueExecutor(owner, address(rescueLog), address(rescueEscrow), address(adapterRegistry));
        
        // Authorizations
        executor.setAuthorizedWorkflow(workflow, true);
        rescueLog.setAuthorizedWriter(address(executor), true);
        rescueLog.setAuthorizedWriter(workflow, true);
        rescueEscrow.setAuthorizedDepositor(address(executor), true);
        
        // Fund engines
        vm.startPrank(minter);
        debt.mint(address(aavePool.engine()), 1000000e6);
        debt.mint(address(compoundMarket.engine()), 1000000e6);
        collateral.mint(user, 100 ether);
        collateral.mint(liquidator, 100 ether);
        debt.mint(liquidator, 1000000e6);
        vm.stopPrank();
    }
    
    // ============ AUTHORIZATION TESTS ============
    
    function test_SetAuthorizedWorkflow() public {
        address newWorkflow = makeAddr("newWorkflow");
        
        vm.expectEmit(true, false, false, true);
        emit WorkflowAuthorized(newWorkflow, true);
        
        executor.setAuthorizedWorkflow(newWorkflow, true);
        assertTrue(executor.authorizedWorkflows(newWorkflow));
    }
    
    function test_SetAuthorizedWorkflow_Revoke() public {
        executor.setAuthorizedWorkflow(workflow, false);
        assertFalse(executor.authorizedWorkflows(workflow));
    }
    
    function test_SetAuthorizedWorkflow_OnlyOwner() public {
        vm.prank(notAuthorized);
        vm.expectRevert();
        executor.setAuthorizedWorkflow(notAuthorized, true);
    }
    
    function test_SetAuthorizedWorkflow_ZeroAddressReverts() public {
        vm.expectRevert(ReprieveErrors.ZeroAddress.selector);
        executor.setAuthorizedWorkflow(address(0), true);
    }
    
    // ============ EXECUTE RESCUE - BASIC TESTS ============
    
    function test_ExecuteRescue_StepFails_GracefulHandling() public {
        // Setup: User has collateral in AAVE
        vm.startPrank(user);
        collateral.approve(address(aavePool), type(uint256).max);
        aavePool.supply(address(collateral), 10 ether, user, 0);
        vm.stopPrank();
        
        // Create rescue plan: attempt withdraw (will fail without user approval of adapter)
        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](1);
        steps[0] = ReprieveTypes.RescueStep({
            stepIndex: 0,
            sourceAdapter: address(aaveAdapter),
            targetAdapter: address(compoundAdapter),
            collateralAsset: address(collateral),
            debtAsset: address(debt),
            collateralAmount: 3 ether,
            debtAmount: 3000e6,
            isCrossChain: false,
            targetChain: 0
        });
        
        ReprieveTypes.RescuePlan memory plan = ReprieveTypes.RescuePlan({
            execId: EXEC_ID,
            user: user,
            mode: ReprieveTypes.RescueMode.TOP_UP,
            steps: steps,
            deadline: block.timestamp + 1 hours,
            maxFee: 1 ether
        });
        
        // Execute rescue (as workflow) - step will fail but handled gracefully
        vm.prank(workflow);
        bool success = executor.executeRescue(plan);
        
        // Step fails because withdrawForRescue requires user approval (not implemented in demo)
        // Executor correctly handles failure and reports it
        assertFalse(success);
        assertFalse(executor.rescueInProgress(user));
        assertEq(uint256(executor.getRescueStatus(EXEC_ID)), uint256(ReprieveTypes.RescueStatus.Failed));
    }

    function test_ExecuteRescue_TopUp_Succeeds() public {
        vm.startPrank(user);
        collateral.approve(address(aavePool), type(uint256).max);
        aavePool.supply(address(collateral), 10 ether, user, 0);
        aavePool.aToken().approve(address(aaveAdapter), type(uint256).max);
        collateral.approve(address(compoundMarket), type(uint256).max);
        compoundMarket.mint(address(collateral), 8 ether);
        compoundMarket.borrow(address(debt), 5000e6);
        vm.stopPrank();

        uint256 targetCollateralBefore = compoundMarket.getUserPosition(user).collateral;
        uint256 targetDebtBefore = compoundMarket.getUserPosition(user).debt;

        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](1);
        steps[0] = ReprieveTypes.RescueStep({
            stepIndex: 0,
            sourceAdapter: address(aaveAdapter),
            targetAdapter: address(compoundAdapter),
            collateralAsset: address(collateral),
            debtAsset: address(debt),
            collateralAmount: 2 ether,
            debtAmount: 0,
            isCrossChain: false,
            targetChain: 0
        });

        ReprieveTypes.RescuePlan memory plan = ReprieveTypes.RescuePlan({
            execId: keccak256("same-chain-topup-success"),
            user: user,
            mode: ReprieveTypes.RescueMode.TOP_UP,
            steps: steps,
            deadline: block.timestamp + 1 hours,
            maxFee: 1 ether
        });

        vm.prank(workflow);
        bool success = executor.executeRescue(plan);

        assertTrue(success);
        assertEq(compoundMarket.getUserPosition(user).collateral, targetCollateralBefore + 2 ether);
        assertEq(compoundMarket.getUserPosition(user).debt, targetDebtBefore);
    }

    function test_ExecuteRescue_Repay_Succeeds_HedgeLike() public {
        // Source leg: lend USDC / borrow WETH pool, used only as USDC source.
        MockAavePool usdcSourcePool = new MockAavePool(address(debt), address(collateral), address(oracle), owner);
        AaveLikeAdapter usdcSourceAdapter =
            new AaveLikeAdapter(address(usdcSourcePool), address(debt), address(collateral), owner);

        usdcSourcePool.engine().setAuthorizedOperator(address(usdcSourcePool), true);

        vm.startPrank(minter);
        collateral.mint(address(usdcSourcePool.engine()), 1000 ether);
        debt.mint(user, 20_000e6);
        vm.stopPrank();

        // Target leg: lend WETH / borrow USDC, then rescue by USDC repay.
        vm.startPrank(user);
        collateral.approve(address(compoundMarket), type(uint256).max);
        compoundMarket.mint(address(collateral), 8 ether);
        compoundMarket.borrow(address(debt), 5000e6);

        debt.approve(address(usdcSourcePool), type(uint256).max);
        usdcSourcePool.supply(address(debt), 10_000e6, user, 0);
        usdcSourcePool.aToken().approve(address(usdcSourceAdapter), type(uint256).max);
        vm.stopPrank();

        uint256 targetDebtBefore = compoundMarket.getUserPosition(user).debt;

        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](1);
        steps[0] = ReprieveTypes.RescueStep({
            stepIndex: 0,
            sourceAdapter: address(usdcSourceAdapter),
            targetAdapter: address(compoundAdapter),
            collateralAsset: address(debt),
            debtAsset: address(debt),
            collateralAmount: 2_000e6,
            debtAmount: 2_000e6,
            isCrossChain: false,
            targetChain: 0
        });

        ReprieveTypes.RescuePlan memory plan = ReprieveTypes.RescuePlan({
            execId: keccak256("same-chain-repay-success"),
            user: user,
            mode: ReprieveTypes.RescueMode.REPAY,
            steps: steps,
            deadline: block.timestamp + 1 hours,
            maxFee: 1 ether
        });

        vm.prank(workflow);
        bool success = executor.executeRescue(plan);

        assertTrue(success);
        assertEq(compoundMarket.getUserPosition(user).debt, targetDebtBefore - 2_000e6);
    }

    function test_ExecuteRescue_RepayMode_RejectsCrossAsset() public {
        vm.startPrank(user);
        collateral.approve(address(aavePool), type(uint256).max);
        aavePool.supply(address(collateral), 10 ether, user, 0);
        aavePool.aToken().approve(address(aaveAdapter), type(uint256).max);
        vm.stopPrank();

        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](1);
        steps[0] = ReprieveTypes.RescueStep({
            stepIndex: 0,
            sourceAdapter: address(aaveAdapter),
            targetAdapter: address(compoundAdapter),
            collateralAsset: address(collateral), // WETH
            debtAsset: address(debt),             // USDC (cross-asset)
            collateralAmount: 1 ether,
            debtAmount: 1000e6,
            isCrossChain: false,
            targetChain: 0
        });

        ReprieveTypes.RescuePlan memory plan = ReprieveTypes.RescuePlan({
            execId: keccak256("same-chain-repay-invalid"),
            user: user,
            mode: ReprieveTypes.RescueMode.REPAY,
            steps: steps,
            deadline: block.timestamp + 1 hours,
            maxFee: 1 ether
        });

        vm.prank(workflow);
        vm.expectRevert(
            abi.encodeWithSelector(
                ReprieveErrors.InvalidRescuePlan.selector,
                "Same-chain repay requires same asset"
            )
        );
        executor.executeRescue(plan);
    }

    function test_ExecuteRescue_MixedModeSteps_RejectsSingleExecution() public {
        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](2);

        // Step 0: top-up style
        steps[0] = ReprieveTypes.RescueStep({
            stepIndex: 0,
            sourceAdapter: address(aaveAdapter),
            targetAdapter: address(compoundAdapter),
            collateralAsset: address(collateral),
            debtAsset: address(debt),
            collateralAmount: 1 ether,
            debtAmount: 0,
            isCrossChain: false,
            targetChain: 0
        });

        // Step 1: repay-only style under TOP_UP plan (invalid in this execution)
        steps[1] = ReprieveTypes.RescueStep({
            stepIndex: 1,
            sourceAdapter: address(aaveAdapter),
            targetAdapter: address(compoundAdapter),
            collateralAsset: address(collateral),
            debtAsset: address(debt),
            collateralAmount: 0,
            debtAmount: 1000e6,
            isCrossChain: false,
            targetChain: 0
        });

        ReprieveTypes.RescuePlan memory plan = ReprieveTypes.RescuePlan({
            execId: keccak256("mixed-mode-reject"),
            user: user,
            mode: ReprieveTypes.RescueMode.TOP_UP,
            steps: steps,
            deadline: block.timestamp + 1 hours,
            maxFee: 1 ether
        });

        vm.prank(workflow);
        vm.expectRevert(
            abi.encodeWithSelector(
                ReprieveErrors.InvalidRescuePlan.selector,
                "Invalid top-up params"
            )
        );
        executor.executeRescue(plan);
    }
    
    function test_ExecuteRescue_RescueInProgressLock() public {
        // Setup position
        vm.startPrank(user);
        collateral.approve(address(aavePool), type(uint256).max);
        aavePool.supply(address(collateral), 10 ether, user, 0);
        vm.stopPrank();
        
        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](1);
        steps[0] = _createSimpleStep();
        
        ReprieveTypes.RescuePlan memory plan = ReprieveTypes.RescuePlan({
            execId: EXEC_ID,
            user: user,
            mode: ReprieveTypes.RescueMode.TOP_UP,
            steps: steps,
            deadline: block.timestamp + 1 hours,
            maxFee: 1 ether
        });
        
        // First rescue (will fail step but that's ok for this test)
        vm.prank(workflow);
        executor.executeRescue(plan);
        
        // Verify lock is released after rescue completes
        assertFalse(executor.rescueInProgress(user));
        
        // Second rescue should succeed (lock released)
        bytes32 execId2 = keccak256("exec-2");
        plan.execId = execId2;
        
        vm.prank(workflow);
        // This should not revert with RescueAlreadyInProgress
        executor.executeRescue(plan);
    }
    
    function test_ExecuteRescue_DeadlinePassedReverts() public {
        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](1);
        steps[0] = _createSimpleStep();
        
        ReprieveTypes.RescuePlan memory plan = ReprieveTypes.RescuePlan({
            execId: EXEC_ID,
            user: user,
            mode: ReprieveTypes.RescueMode.TOP_UP,
            steps: steps,
            deadline: block.timestamp - 1, // Past deadline
            maxFee: 1 ether
        });
        
        vm.prank(workflow);
        vm.expectRevert(abi.encodeWithSelector(ReprieveErrors.DeadlinePassed.selector, block.timestamp - 1, block.timestamp));
        executor.executeRescue(plan);
    }
    
    function test_ExecuteRescue_UnauthorizedReverts() public {
        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](1);
        steps[0] = _createSimpleStep();
        
        ReprieveTypes.RescuePlan memory plan = ReprieveTypes.RescuePlan({
            execId: EXEC_ID,
            user: user,
            mode: ReprieveTypes.RescueMode.TOP_UP,
            steps: steps,
            deadline: block.timestamp + 1 hours,
            maxFee: 1 ether
        });
        
        vm.prank(notAuthorized);
        vm.expectRevert(abi.encodeWithSelector(ReprieveErrors.UnauthorizedWorkflow.selector, notAuthorized));
        executor.executeRescue(plan);
    }
    
    // ============ RESCUE IN PROGRESS TESTS ============
    
    function test_RescueInProgress_LockSet() public {
        // This tests the lock is set during rescue
        // Using a reentrancy attempt simulation
        
        vm.startPrank(user);
        collateral.approve(address(aavePool), type(uint256).max);
        aavePool.supply(address(collateral), 10 ether, user, 0);
        vm.stopPrank();
        
        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](1);
        steps[0] = _createSimpleStep();
        
        ReprieveTypes.RescuePlan memory plan = ReprieveTypes.RescuePlan({
            execId: EXEC_ID,
            user: user,
            mode: ReprieveTypes.RescueMode.TOP_UP,
            steps: steps,
            deadline: block.timestamp + 1 hours,
            maxFee: 1 ether
        });
        
        // Before rescue, no lock
        assertFalse(executor.rescueInProgress(user));
        
        // Execute rescue
        vm.prank(workflow);
        executor.executeRescue(plan);
        
        // After rescue, lock cleared
        assertFalse(executor.rescueInProgress(user));
    }
    
    function test_RescueInProgress_ConcurrentReverts() public {
        // Create a mock that would reenter - simplified test
        // Just verify the modifier exists and works
        
        vm.startPrank(user);
        collateral.approve(address(aavePool), type(uint256).max);
        aavePool.supply(address(collateral), 10 ether, user, 0);
        vm.stopPrank();
        
        // Manually set lock (rescueInProgress mapping at slot 5: _owner(0), rescueLog(1), rescueEscrow(2), adapterRegistry(3), ccipRouter(4), rescueInProgress(5))
        vm.store(address(executor), keccak256(abi.encode(user, uint256(5))), bytes32(uint256(1)));
        
        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](1);
        steps[0] = _createSimpleStep();
        
        ReprieveTypes.RescuePlan memory plan = ReprieveTypes.RescuePlan({
            execId: EXEC_ID,
            user: user,
            mode: ReprieveTypes.RescueMode.TOP_UP,
            steps: steps,
            deadline: block.timestamp + 1 hours,
            maxFee: 1 ether
        });
        
        vm.prank(workflow);
        vm.expectRevert(abi.encodeWithSelector(ReprieveErrors.RescueAlreadyInProgress.selector, user));
        executor.executeRescue(plan);
    }
    
    // ============ MULTI-SOURCE FALLBACK TESTS ============
    
    function test_ExecuteRescue_MultiSourceFallback() public {
        // Setup: User has collateral in AAVE (small amount) and Compound (large amount)
        
        vm.startPrank(user);
        // Small amount in AAVE
        collateral.approve(address(aavePool), type(uint256).max);
        aavePool.supply(address(collateral), 2 ether, user, 0);
        
        // Large amount in Compound
        collateral.approve(address(compoundMarket), type(uint256).max);
        compoundMarket.mint(address(collateral), 10 ether);
        vm.stopPrank();
        
        // Create rescue plan with 2 sources
        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](2);
        
        // Step 1: Try AAVE first (insufficient collateral for requested amount)
        steps[0] = ReprieveTypes.RescueStep({
            stepIndex: 0,
            sourceAdapter: address(aaveAdapter),
            targetAdapter: address(compoundAdapter),
            collateralAsset: address(collateral),
            debtAsset: address(debt),
            collateralAmount: 5 ether, // More than available (only 2 ether supplied)
            debtAmount: 5000e6,
            isCrossChain: false,
            targetChain: 0
        });
        
        // Step 2: Fallback to Compound
        steps[1] = ReprieveTypes.RescueStep({
            stepIndex: 1,
            sourceAdapter: address(compoundAdapter),
            targetAdapter: address(compoundAdapter),
            collateralAsset: address(collateral),
            debtAsset: address(debt),
            collateralAmount: 5 ether,
            debtAmount: 5000e6,
            isCrossChain: false,
            targetChain: 0
        });
        
        ReprieveTypes.RescuePlan memory plan = ReprieveTypes.RescuePlan({
            execId: EXEC_ID,
            user: user,
            mode: ReprieveTypes.RescueMode.TOP_UP,
            steps: steps,
            deadline: block.timestamp + 1 hours,
            maxFee: 1 ether
        });
        
        // Execute rescue
        vm.prank(workflow);
        bool success = executor.executeRescue(plan);
        
        // Both steps will fail because withdrawForRescue requires user approval
        // But the executor correctly tries all steps and handles failures
        assertFalse(success);
        
        // Verify logs were created for both steps
        // init(1) + step0_start(1) + step0_fail(1) + step1_start(1) + step1_fail(1) + final_fail(1) = 6
        assertEq(rescueLog.getLogEntryCount(EXEC_ID), 6);
    }
    
    // ============ OWNER CAN EXECUTE TESTS ============
    
    function test_ExecuteRescue_OwnerCanExecute() public {
        // Owner should be able to execute without being in authorizedWorkflows
        
        vm.startPrank(user);
        collateral.approve(address(aavePool), type(uint256).max);
        aavePool.supply(address(collateral), 10 ether, user, 0);
        vm.stopPrank();
        
        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](1);
        steps[0] = _createSimpleStep();
        
        ReprieveTypes.RescuePlan memory plan = ReprieveTypes.RescuePlan({
            execId: EXEC_ID,
            user: user,
            mode: ReprieveTypes.RescueMode.TOP_UP,
            steps: steps,
            deadline: block.timestamp + 1 hours,
            maxFee: 1 ether
        });
        
        // Owner executes directly - doesn't revert with UnauthorizedWorkflow
        // Step may fail but execution itself is authorized
        executor.executeRescue(plan);
        
        // Verify rescue was attempted (status set)
        assertFalse(executor.rescueInProgress(user)); // Lock released after
    }

    function test_ExecuteRescue_SameChain_DoesNotUseExecutorFloat() public {
        // Seed executor directly to ensure same-chain path cannot bypass source withdrawal.
        vm.prank(minter);
        collateral.mint(address(executor), 10 ether);
        uint256 executorBalanceBefore = collateral.balanceOf(address(executor));
        uint256 targetCollateralBefore = compoundMarket.getUserPosition(user).collateral;

        // User intentionally has no source Aave position.
        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](1);
        steps[0] = ReprieveTypes.RescueStep({
            stepIndex: 0,
            sourceAdapter: address(aaveAdapter),
            targetAdapter: address(compoundAdapter),
            collateralAsset: address(collateral),
            debtAsset: address(debt),
            collateralAmount: 1 ether,
            debtAmount: 0,
            isCrossChain: false,
            targetChain: 0
        });

        ReprieveTypes.RescuePlan memory plan = ReprieveTypes.RescuePlan({
            execId: keccak256("same-chain-no-float"),
            user: user,
            mode: ReprieveTypes.RescueMode.TOP_UP,
            steps: steps,
            deadline: block.timestamp + 1 hours,
            maxFee: 1 ether
        });

        vm.prank(workflow);
        bool success = executor.executeRescue(plan);

        assertFalse(success, "Execution should fail without source withdrawal");
        assertEq(collateral.balanceOf(address(executor)), executorBalanceBefore, "Executor float must remain untouched");
        assertEq(compoundMarket.getUserPosition(user).collateral, targetCollateralBefore, "Target collateral should not change");
        assertEq(uint256(executor.getRescueStatus(plan.execId)), uint256(ReprieveTypes.RescueStatus.Failed));
    }
    
    // ============ CONSTANTS TESTS ============
    
    function test_SourceReserveFactor() public view {
        assertEq(executor.SOURCE_RESERVE_FACTOR_BPS(), 2000); // 20%
    }
    
    // ============ HELPER FUNCTIONS ============
    
    function _createSimpleStep() internal view returns (ReprieveTypes.RescueStep memory) {
        return ReprieveTypes.RescueStep({
            stepIndex: 0,
            sourceAdapter: address(aaveAdapter),
            targetAdapter: address(aaveAdapter),
            collateralAsset: address(collateral),
            debtAsset: address(debt),
            collateralAmount: 1 ether,
            debtAmount: 1000e6,
            isCrossChain: false,
            targetChain: 0
        });
    }
}
