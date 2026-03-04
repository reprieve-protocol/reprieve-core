// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockCCIPRouter} from "../../src/mocks/MockCCIPRouter.sol";
import {CCIPReceiver} from "../../src/reprieve/CCIPReceiver.sol";
import {RescueExecutor} from "../../src/reprieve/RescueExecutor.sol";
import {RescueEscrow} from "../../src/reprieve/RescueEscrow.sol";
import {RescueLog} from "../../src/reprieve/RescueLog.sol";
import {AdapterRegistry} from "../../src/reprieve/AdapterRegistry.sol";
import {AaveLikeAdapter} from "../../src/adapters/AaveLikeAdapter.sol";
import {CompoundLikeAdapter} from "../../src/adapters/CompoundLikeAdapter.sol";
import {MockAavePool} from "../../src/mocks/MockAavePool.sol";
import {MockCompoundMarket} from "../../src/mocks/MockCompoundMarket.sol";
import {BaseLendingEngine} from "../../src/mocks/BaseLendingEngine.sol";
import {MockPriceOracle} from "../../src/mocks/MockPriceOracle.sol";
import {ReprieveTypes} from "../../src/reprieve/libs/ReprieveTypes.sol";

/**
 * @title CrossChainIntegrationTest
 * @notice End-to-end cross-chain rescue test using MockCCIPRouter
 * @dev Both "source" and "destination" are on the same chain for testing
 */
contract CrossChainIntegrationTest is Test {
    
    // Contracts on "Source Chain" (Ethereum Sepolia simulation)
    RescueExecutor sourceExecutor;
    RescueLog sourceLog;
    RescueEscrow sourceEscrow;
    AdapterRegistry sourceRegistry;
    AaveLikeAdapter sourceAaveAdapter;
    MockAavePool sourceAavePool;
    
    // Contracts on "Destination Chain" (Base Sepolia simulation)
    RescueExecutor destExecutor;
    RescueLog destLog;
    RescueEscrow destEscrow;
    CCIPReceiver destReceiver;
    AdapterRegistry destRegistry;
    CompoundLikeAdapter destCompoundAdapter;
    MockCompoundMarket destCompoundMarket;
    
    // Shared infrastructure
    MockCCIPRouter ccipRouter;
    MockERC20 collateral;  // WETH
    MockERC20 debt;        // USDC
    MockERC20 linkToken;
    MockPriceOracle oracle;
    
    // Test actors
    address owner;
    address workflow;
    address user;
    address minter;
    
    // Chain selectors
    uint64 constant SOURCE_CHAIN_SELECTOR = 16015286601757825753; // Ethereum Sepolia
    uint64 constant DEST_CHAIN_SELECTOR = 10344971235874465080;   // Base Sepolia
    
    bytes32 constant EXEC_ID = keccak256("cross-chain-rescue-1");
    
    function setUp() public {
        owner = address(this);
        workflow = makeAddr("workflow");
        user = makeAddr("user");
        minter = makeAddr("minter");
        
        // Deploy tokens
        collateral = new MockERC20("WETH", "WETH", 18, minter);
        debt = new MockERC20("USDC", "USDC", 6, minter);
        linkToken = new MockERC20("LINK", "LINK", 18, minter);
        
        // Deploy oracle and set prices (WETH @ $2000, USDC @ $1)
        // Note: MockPriceOracle stores prices in WAD (18 decimals)
        oracle = new MockPriceOracle(owner, 30 minutes);
        oracle.setPrice(address(collateral), 2000e18);  // WETH @ $2000
        oracle.setPrice(address(debt), 1e18);           // USDC @ $1
        
        // Deploy CCIP Router
        ccipRouter = new MockCCIPRouter(address(linkToken));
        ccipRouter.setCurrentChainSelector(SOURCE_CHAIN_SELECTOR);
        ccipRouter.setLane(SOURCE_CHAIN_SELECTOR, DEST_CHAIN_SELECTOR, true);
        ccipRouter.setTokenMapping(DEST_CHAIN_SELECTOR, address(collateral), address(collateral));
        
        // ============ SOURCE CHAIN SETUP ============
        sourceLog = new RescueLog(owner);
        sourceEscrow = new RescueEscrow(owner, address(sourceLog));
        sourceRegistry = new AdapterRegistry(owner);
        sourceRegistry.initializeDemoProtocols();
        
        // Deploy source lending protocol (AAVE-like)
        sourceAavePool = new MockAavePool(address(collateral), address(debt), address(oracle), owner);
        sourceAavePool.engine().setAuthorizedOperator(address(sourceAavePool), true);
        // MockAToken aToken = sourceAavePool.aToken(); // Unused variable
        
        sourceAaveAdapter = new AaveLikeAdapter(
            address(sourceAavePool),
            address(collateral),
            address(debt),
            owner
        );
        
        // Source Executor
        sourceExecutor = new RescueExecutor(
            owner,
            address(sourceLog),
            address(sourceEscrow),
            address(sourceRegistry)
        );
        sourceExecutor.setAuthorizedWorkflow(workflow, true);
        sourceExecutor.setCcipRouter(address(ccipRouter));
        sourceExecutor.setTrustedDestinationChain(DEST_CHAIN_SELECTOR, true);
        sourceLog.setAuthorizedWriter(address(sourceExecutor), true);
        
        // ============ DESTINATION CHAIN SETUP ============
        destLog = new RescueLog(owner);
        destEscrow = new RescueEscrow(owner, address(destLog));
        destRegistry = new AdapterRegistry(owner);
        destRegistry.initializeDemoProtocols();
        
        // Deploy destination lending protocol (Compound-like)
        destCompoundMarket = new MockCompoundMarket(address(collateral), address(debt), address(oracle), owner);
        
        destCompoundAdapter = new CompoundLikeAdapter(
            address(destCompoundMarket),
            address(collateral),
            address(debt),
            address(destCompoundMarket.cToken()),
            owner
        );
        
        // Destination Executor
        destExecutor = new RescueExecutor(
            owner,
            address(destLog),
            address(destEscrow),
            address(destRegistry)
        );
        destExecutor.setAuthorizedWorkflow(address(this), true); // Allow tests to call
        destLog.setAuthorizedWriter(address(destExecutor), true);
        
        // Destination CCIP Receiver
        destReceiver = new CCIPReceiver(
            owner,
            address(destExecutor),
            address(destEscrow),
            address(destLog)
        );
        destReceiver.setRouter(address(ccipRouter));
        destReceiver.setAllowedSourceChain(SOURCE_CHAIN_SELECTOR, true);
        destReceiver.setAllowedSender(SOURCE_CHAIN_SELECTOR, address(sourceExecutor), true);
        destEscrow.setAuthorizedDepositor(address(destReceiver), true);
        destLog.setAuthorizedWriter(address(destReceiver), true);
        ccipRouter.setReceiver(DEST_CHAIN_SELECTOR, address(destReceiver));
        
        // Link destReceiver to destExecutor
        destExecutor.setCcipRouter(address(ccipRouter)); // For any callbacks
        
        // Set chain receiver for cross-chain calls
        sourceExecutor.setChainReceiver(DEST_CHAIN_SELECTOR, address(destReceiver));

        // Authorize bridge roles for burn on source + mint on destination.
        vm.prank(minter);
        collateral.setBridgeBurner(address(ccipRouter), true);
        vm.prank(minter);
        collateral.setBridgeMinter(address(ccipRouter), true);
        
        // Fund accounts
        vm.prank(minter);
        collateral.mint(user, 100 ether);
        vm.prank(minter);
        debt.mint(user, 10000e6);
        vm.prank(minter);
        linkToken.mint(address(sourceExecutor), 100 ether); // For CCIP fees
        vm.prank(minter);
        linkToken.mint(user, 10 ether);
        
        // Fund sourceExecutor with ETH for CCIP fees.
        vm.deal(address(sourceExecutor), 10 ether); // Fund with ETH for CCIP fees
        
        // Fund Compound engine with debt tokens for borrowing
        BaseLendingEngine compoundEngine = destCompoundMarket.engine();
        vm.prank(minter);
        debt.mint(address(compoundEngine), 50000e6); // $50k USDC for lending
        
    }
    
    // ============ END-TO-END CROSS-CHAIN RESCUE TEST ============
    
    function test_FullCrossChainRescue() public {
        // =====================================
        // SETUP: User has collateral in AAVE (source)
        //        User has debt in Compound (destination)
        // =====================================
        
        // User supplies collateral to source AAVE
        vm.startPrank(user);
        collateral.approve(address(sourceAavePool), type(uint256).max);
        sourceAavePool.supply(address(collateral), 10 ether, user, 0);
        sourceAavePool.aToken().approve(address(sourceAaveAdapter), type(uint256).max);
        vm.stopPrank();
        
        // User supplies collateral and borrows debt from destination Compound
        // Need sufficient collateral to borrow 5000 USDC (at 75% LTV, need ~$6667 collateral = 3.33 ETH)
        vm.startPrank(user);
        collateral.approve(address(destCompoundMarket), type(uint256).max);
        debt.approve(address(destCompoundMarket), type(uint256).max);
        destCompoundMarket.mint(address(collateral), 8 ether); // Supply 8 ETH ($16,000)
        destCompoundMarket.borrow(address(debt), 5000e6);      // Borrow $5,000 USDC
        vm.stopPrank();
        
        // Verify initial state
        assertGt(sourceAavePool.getUserPosition(user).collateral, 0);
        assertGt(destCompoundMarket.getUserPosition(user).debt, 0);
        
        // =====================================
        // STEP 1: Initiate Cross-Chain Rescue
        // =====================================
        
        // Build rescue step
        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](1);
        steps[0] = ReprieveTypes.RescueStep({
            stepIndex: 0,
            sourceAdapter: address(sourceAaveAdapter),
            targetAdapter: address(destCompoundAdapter),
            collateralAsset: address(collateral),
            debtAsset: address(debt),
            collateralAmount: 4 ether,
            debtAmount: 4000e6,
            isCrossChain: true,
            targetChain: DEST_CHAIN_SELECTOR
        });
        
        ReprieveTypes.RescuePlan memory plan = ReprieveTypes.RescuePlan({
            execId: EXEC_ID,
            user: user,
            mode: ReprieveTypes.RescueMode.TOP_UP,
            steps: steps,
            deadline: block.timestamp + 1 hours,
            maxFee: 1 ether
        });
        
        // Approve router to spend tokens
        vm.prank(address(sourceExecutor));
        collateral.approve(address(ccipRouter), type(uint256).max);
        
        // Approve LINK for fees
        vm.prank(address(sourceExecutor));
        linkToken.approve(address(ccipRouter), type(uint256).max);
        
        uint256 sourceSupplyBefore = collateral.totalSupply();

        // Execute rescue (as workflow)
        vm.prank(workflow);
        bool success = sourceExecutor.executeRescue(plan);
        
        assertTrue(success, "Rescue execution should succeed");
        
        // Get message ID from executor
        bytes32 messageId = sourceExecutor.ccipMessageIds(EXEC_ID);
        assertNotEq(messageId, bytes32(0), "Message ID should be set");
        
        // Verify message stored in router
        MockCCIPRouter.StoredMessage memory stored = ccipRouter.getMessage(messageId);
        assertEq(stored.sender, address(sourceExecutor));
        assertEq(stored.destinationChainSelector, DEST_CHAIN_SELECTOR);
        assertEq(stored.tokenAmounts.length, 1);
        assertEq(stored.tokenAmounts[0].token, address(collateral));
        assertEq(stored.tokenAmounts[0].amount, 4 ether);
        assertEq(uint256(ccipRouter.messageStatus(messageId)), uint256(MockCCIPRouter.MessageStatus.Pending));
        assertEq(collateral.totalSupply(), sourceSupplyBefore - 4 ether);

        ReprieveTypes.CCIPMessage memory payload = abi.decode(stored.data, (ReprieveTypes.CCIPMessage));
        assertEq(uint256(payload.mode), uint256(ReprieveTypes.RescueMode.TOP_UP));
        assertEq(payload.asset, address(collateral));
        assertEq(payload.amount, 4 ether);
        
        // =====================================
        // STEP 2: CCIP Delivers Message
        // =====================================
        uint256 collateralSupplyAfterBurn = collateral.totalSupply();
        uint256 receiverCollateralBefore = collateral.balanceOf(address(destReceiver));
        uint256 destCollateralBefore = destCompoundMarket.getUserPosition(user).collateral;
        uint256 destDebtBefore = destCompoundMarket.getUserPosition(user).debt;
        
        // Deliver message (simulating CCIP)
        ccipRouter.deliverMessage(messageId);
        
        assertEq(uint256(ccipRouter.messageStatus(messageId)), uint256(MockCCIPRouter.MessageStatus.Delivered));
        assertEq(collateral.totalSupply(), collateralSupplyAfterBurn + 4 ether);
        assertEq(collateral.balanceOf(address(destReceiver)), receiverCollateralBefore);
        assertEq(destCompoundMarket.getUserPosition(user).collateral, destCollateralBefore + 4 ether);
        assertEq(destCompoundMarket.getUserPosition(user).debt, destDebtBefore);
        
        // =====================================
        // STEP 3: Verify State Changes
        // =====================================
        
        // Check message was processed
        assertTrue(destReceiver.processedMessages(messageId));
        
        // Check rescue status on source executor (should be Completed after successful cross-chain)
        assertEq(uint256(sourceExecutor.getRescueStatus(EXEC_ID)), uint256(ReprieveTypes.RescueStatus.Completed));
    }

    function test_CrossChainRescue_DoesNotUseExecutorFloat() public {
        // Seed executor directly to ensure cross-chain path cannot bypass source withdrawal.
        vm.prank(minter);
        collateral.mint(address(sourceExecutor), 10 ether);
        uint256 executorBalanceBefore = collateral.balanceOf(address(sourceExecutor));

        // User intentionally has no source Aave position here.
        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](1);
        steps[0] = ReprieveTypes.RescueStep({
            stepIndex: 0,
            sourceAdapter: address(sourceAaveAdapter),
            targetAdapter: address(destCompoundAdapter),
            collateralAsset: address(collateral),
            debtAsset: address(debt),
            collateralAmount: 1 ether,
            debtAmount: 0,
            isCrossChain: true,
            targetChain: DEST_CHAIN_SELECTOR
        });

        ReprieveTypes.RescuePlan memory plan = ReprieveTypes.RescuePlan({
            execId: EXEC_ID,
            user: user,
            mode: ReprieveTypes.RescueMode.TOP_UP,
            steps: steps,
            deadline: block.timestamp + 1 hours,
            maxFee: 1 ether
        });

        vm.prank(workflow);
        bool success = sourceExecutor.executeRescue(plan);

        assertFalse(success, "Execution should fail without source position withdrawal");
        assertEq(sourceExecutor.ccipMessageIds(EXEC_ID), bytes32(0), "No CCIP message should be sent");
        assertEq(collateral.balanceOf(address(sourceExecutor)), executorBalanceBefore, "Executor float must remain untouched");
        assertEq(uint256(sourceExecutor.getRescueStatus(EXEC_ID)), uint256(ReprieveTypes.RescueStatus.Failed));
    }
    
    function test_CrossChainRescue_WithFailureRetry() public {
        // Setup similar position
        vm.startPrank(user);
        collateral.approve(address(sourceAavePool), type(uint256).max);
        sourceAavePool.supply(address(collateral), 10 ether, user, 0);
        sourceAavePool.aToken().approve(address(sourceAaveAdapter), type(uint256).max);
        vm.stopPrank();
        
        // Build rescue step
        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](1);
        steps[0] = ReprieveTypes.RescueStep({
            stepIndex: 0,
            sourceAdapter: address(sourceAaveAdapter),
            targetAdapter: address(destCompoundAdapter),
            collateralAsset: address(collateral),
            debtAsset: address(debt),
            collateralAmount: 4 ether,
            debtAmount: 4000e6,
            isCrossChain: true,
            targetChain: DEST_CHAIN_SELECTOR
        });
        
        ReprieveTypes.RescuePlan memory plan = ReprieveTypes.RescuePlan({
            execId: EXEC_ID,
            user: user,
            mode: ReprieveTypes.RescueMode.TOP_UP,
            steps: steps,
            deadline: block.timestamp + 1 hours,
            maxFee: 1 ether
        });
        
        // Approve tokens
        vm.prank(address(sourceExecutor));
        collateral.approve(address(ccipRouter), type(uint256).max);
        vm.prank(address(sourceExecutor));
        linkToken.approve(address(ccipRouter), type(uint256).max);
        
        // Execute rescue
        vm.prank(workflow);
        sourceExecutor.executeRescue(plan);
        
        bytes32 messageId = sourceExecutor.ccipMessageIds(EXEC_ID);
        
        // Warp past deadline to cause failure
        vm.warp(block.timestamp + 2 hours);
        
        // Delivery should handle failure gracefully
        ccipRouter.deliverMessage(messageId);
        
        // Check failure was recorded
        CCIPReceiver.FailedMessage memory failed = destReceiver.getFailedMessage(messageId);
        assertEq(failed.messageId, messageId);
        assertFalse(failed.recovered);
        
        // Funds should be in escrow
        // Get escrow ID from failed message record (already fetched above)
        assertNotEq(failed.escrowId, bytes32(0), "Escrow ID should be set");
        
        // Check escrow record exists with correct asset and amount
        ReprieveTypes.EscrowRecord memory record = destEscrow.getEscrow(failed.escrowId);
        assertEq(record.asset, address(collateral));
        assertGt(record.amount, 0);
    }

    function test_CrossChainRescue_MappingMismatch_EscrowsFunds() public {
        // Override lane mapping to an incompatible token for top-up.
        ccipRouter.setTokenMapping(DEST_CHAIN_SELECTOR, address(collateral), address(debt));

        // Allow router mint/burn roles for the mismatched destination token.
        vm.prank(minter);
        debt.setBridgeMinter(address(ccipRouter), true);
        vm.prank(minter);
        debt.setBridgeBurner(address(ccipRouter), true);

        vm.startPrank(user);
        collateral.approve(address(sourceAavePool), type(uint256).max);
        sourceAavePool.supply(address(collateral), 10 ether, user, 0);
        sourceAavePool.aToken().approve(address(sourceAaveAdapter), type(uint256).max);
        vm.stopPrank();

        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](1);
        steps[0] = ReprieveTypes.RescueStep({
            stepIndex: 0,
            sourceAdapter: address(sourceAaveAdapter),
            targetAdapter: address(destCompoundAdapter),
            collateralAsset: address(collateral),
            debtAsset: address(debt),
            collateralAmount: 1 ether,
            debtAmount: 1000e6,
            isCrossChain: true,
            targetChain: DEST_CHAIN_SELECTOR
        });

        ReprieveTypes.RescuePlan memory plan = ReprieveTypes.RescuePlan({
            execId: EXEC_ID,
            user: user,
            mode: ReprieveTypes.RescueMode.TOP_UP,
            steps: steps,
            deadline: block.timestamp + 1 hours,
            maxFee: 1 ether
        });

        vm.prank(address(sourceExecutor));
        collateral.approve(address(ccipRouter), type(uint256).max);
        vm.prank(address(sourceExecutor));
        linkToken.approve(address(ccipRouter), type(uint256).max);

        vm.prank(workflow);
        sourceExecutor.executeRescue(plan);

        bytes32 messageId = sourceExecutor.ccipMessageIds(EXEC_ID);
        ccipRouter.deliverMessage(messageId);

        CCIPReceiver.FailedMessage memory failed = destReceiver.getFailedMessage(messageId);
        assertEq(failed.messageId, messageId);
        assertNotEq(failed.escrowId, bytes32(0));

        ReprieveTypes.EscrowRecord memory record = destEscrow.getEscrow(failed.escrowId);
        assertEq(record.asset, address(debt));
        assertEq(record.amount, 1 ether);
    }

    function test_CrossChainRescue_RepayMode_Succeeds() public {
        // Repay mode branch: source collateral maps to destination debt token.
        ccipRouter.setTokenMapping(DEST_CHAIN_SELECTOR, address(collateral), address(debt));

        vm.prank(minter);
        debt.setBridgeMinter(address(ccipRouter), true);
        vm.prank(minter);
        debt.setBridgeBurner(address(ccipRouter), true);

        vm.startPrank(user);
        collateral.approve(address(sourceAavePool), type(uint256).max);
        sourceAavePool.supply(address(collateral), 10 ether, user, 0);
        sourceAavePool.aToken().approve(address(sourceAaveAdapter), type(uint256).max);
        collateral.approve(address(destCompoundMarket), type(uint256).max);
        destCompoundMarket.mint(address(collateral), 8 ether);
        destCompoundMarket.borrow(address(debt), 5000e6);
        vm.stopPrank();

        uint256 destDebtBefore = destCompoundMarket.getUserPosition(user).debt;

        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](1);
        steps[0] = ReprieveTypes.RescueStep({
            stepIndex: 0,
            sourceAdapter: address(sourceAaveAdapter),
            targetAdapter: address(destCompoundAdapter),
            collateralAsset: address(collateral),
            debtAsset: address(debt),
            collateralAmount: 2_000e6,
            debtAmount: 2_000e6,
            isCrossChain: true,
            targetChain: DEST_CHAIN_SELECTOR
        });

        ReprieveTypes.RescuePlan memory plan = ReprieveTypes.RescuePlan({
            execId: EXEC_ID,
            user: user,
            mode: ReprieveTypes.RescueMode.REPAY,
            steps: steps,
            deadline: block.timestamp + 1 hours,
            maxFee: 1 ether
        });

        vm.prank(address(sourceExecutor));
        collateral.approve(address(ccipRouter), type(uint256).max);
        vm.prank(address(sourceExecutor));
        linkToken.approve(address(ccipRouter), type(uint256).max);

        vm.prank(workflow);
        bool success = sourceExecutor.executeRescue(plan);
        assertTrue(success);

        bytes32 messageId = sourceExecutor.ccipMessageIds(EXEC_ID);
        MockCCIPRouter.StoredMessage memory stored = ccipRouter.getMessage(messageId);
        ReprieveTypes.CCIPMessage memory payload = abi.decode(stored.data, (ReprieveTypes.CCIPMessage));
        assertEq(uint256(payload.mode), uint256(ReprieveTypes.RescueMode.REPAY));
        assertEq(payload.asset, address(debt));
        assertEq(payload.amount, 2_000e6);

        ccipRouter.deliverMessage(messageId);

        assertEq(destCompoundMarket.getUserPosition(user).debt, destDebtBefore - 2_000e6);
    }
    
    function test_CrossChain_MessageStructure() public {
        // Test that CCIP message is built correctly
        
        // Setup position
        vm.startPrank(user);
        collateral.approve(address(sourceAavePool), type(uint256).max);
        sourceAavePool.supply(address(collateral), 10 ether, user, 0);
        sourceAavePool.aToken().approve(address(sourceAaveAdapter), type(uint256).max);
        vm.stopPrank();
        
        // Build rescue step
        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](1);
        steps[0] = ReprieveTypes.RescueStep({
            stepIndex: 0,
            sourceAdapter: address(sourceAaveAdapter),
            targetAdapter: address(destCompoundAdapter),
            collateralAsset: address(collateral),
            debtAsset: address(debt),
            collateralAmount: 5 ether,
            debtAmount: 2500e6,
            isCrossChain: true,
            targetChain: DEST_CHAIN_SELECTOR
        });
        
        ReprieveTypes.RescuePlan memory plan = ReprieveTypes.RescuePlan({
            execId: EXEC_ID,
            user: user,
            mode: ReprieveTypes.RescueMode.TOP_UP,
            steps: steps,
            deadline: block.timestamp + 1 hours,
            maxFee: 1 ether
        });
        
        // Approve tokens
        vm.prank(address(sourceExecutor));
        collateral.approve(address(ccipRouter), type(uint256).max);
        vm.prank(address(sourceExecutor));
        linkToken.approve(address(ccipRouter), type(uint256).max);
        
        // Execute
        vm.prank(workflow);
        sourceExecutor.executeRescue(plan);
        
        bytes32 messageId = sourceExecutor.ccipMessageIds(EXEC_ID);
        MockCCIPRouter.StoredMessage memory stored = ccipRouter.getMessage(messageId);
        
        // Verify message structure
        assertEq(stored.destinationChainSelector, DEST_CHAIN_SELECTOR);
        assertEq(_decodeReceiver(stored.receiver), address(destReceiver));
        assertEq(stored.tokenAmounts[0].amount, 5 ether);
        assertEq(stored.tokenAmounts[0].token, address(collateral));

        ReprieveTypes.CCIPMessage memory payload = abi.decode(stored.data, (ReprieveTypes.CCIPMessage));
        assertEq(payload.execId, EXEC_ID);
        assertEq(payload.user, user);
        assertEq(uint256(payload.mode), uint256(ReprieveTypes.RescueMode.TOP_UP));
        assertEq(payload.targetAdapter, address(destCompoundAdapter));
        assertEq(payload.asset, address(collateral));
        assertEq(payload.amount, 5 ether);
    }
    
    // ============ HELPERS ============
    
    function _decodeReceiver(bytes memory receiver) internal pure returns (address) {
        if (receiver.length == 32) {
            return abi.decode(receiver, (address));
        } else if (receiver.length == 20) {
            return address(uint160(bytes20(receiver)));
        }
        revert("Invalid receiver format");
    }
}
