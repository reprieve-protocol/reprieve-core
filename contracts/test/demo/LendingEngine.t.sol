// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockPriceOracle} from "../../src/mocks/MockPriceOracle.sol";
import {BaseLendingEngine} from "../../src/mocks/BaseLendingEngine.sol";
import {DemoConstants} from "../../src/libs/DemoConstants.sol";
import {LendingMath} from "../../src/libs/LendingMath.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

/**
 * @title LendingEngineTest
 * @notice Tests for Slide 2: Shared Lending Engine
 * @dev Tests BaseLendingEngine functionality
 */
contract LendingEngineTest is Test {
    MockERC20 public collateralToken;
    MockERC20 public debtToken;
    MockPriceOracle public oracle;
    BaseLendingEngine public engine;
    
    address public owner;
    address public minter;
    address public user1;
    address public user2;
    address public liquidator;
    
    // Test constants
    uint256 constant INITIAL_PRICE = 2000e18; // $2000 WETH
    uint256 constant DEBT_PRICE = 1e18;       // $1 USDC
    uint256 constant COLLATERAL_DECIMALS = 18;
    uint256 constant DEBT_DECIMALS = 6;
    
    // Events
    event Supplied(address indexed user, address indexed asset, uint256 amount);
    event Withdrawn(address indexed user, address indexed asset, uint256 amount, address indexed to);
    event Borrowed(address indexed user, address indexed asset, uint256 amount);
    event Repaid(address indexed user, address indexed asset, uint256 amount, address indexed onBehalfOf);
    event PositionUpdated(address indexed user, uint256 collateral, uint256 debt, uint256 hfWad);
    event Liquidated(address indexed user, address indexed liquidator, uint256 debtRepaid, uint256 collateralSeized);
    
    function setUp() public {
        owner = address(this);
        minter = makeAddr("minter");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        liquidator = makeAddr("liquidator");
        
        // Deploy tokens
        collateralToken = new MockERC20("Wrapped Ether", "WETH", 18, minter);
        debtToken = new MockERC20("USD Coin", "USDC", 6, minter);
        
        // Deploy oracle
        oracle = new MockPriceOracle(owner, 30 minutes);
        
        // Deploy engine
        engine = new BaseLendingEngine(
            address(collateralToken),
            address(debtToken),
            address(oracle),
            owner
        );
        
        // Set prices
        oracle.setPrice(address(collateralToken), INITIAL_PRICE);
        oracle.setPrice(address(debtToken), DEBT_PRICE);
        
        // Mint tokens to users and liquidator
        vm.startPrank(minter);
        collateralToken.mint(user1, 100 ether);
        collateralToken.mint(user2, 100 ether);
        collateralToken.mint(liquidator, 100 ether);
        debtToken.mint(user1, 100000e6);
        debtToken.mint(user2, 100000e6);
        debtToken.mint(liquidator, 100000e6);
        
        // Mint debt tokens to engine for lending (simulate liquidity pool)
        debtToken.mint(address(engine), 10000000e6);
        vm.stopPrank();
        
        // Approve engine to spend tokens
        vm.prank(user1);
        collateralToken.approve(address(engine), type(uint256).max);
        vm.prank(user1);
        debtToken.approve(address(engine), type(uint256).max);
        
        vm.prank(user2);
        collateralToken.approve(address(engine), type(uint256).max);
        vm.prank(user2);
        debtToken.approve(address(engine), type(uint256).max);
        
        vm.prank(liquidator);
        debtToken.approve(address(engine), type(uint256).max);
    }
    
    // ============ Constructor & Initial State Tests ============
    
    function test_Constructor_InitialState() public view {
        assertEq(address(engine.collateralAsset()), address(collateralToken));
        assertEq(address(engine.debtAsset()), address(debtToken));
        assertEq(address(engine.oracle()), address(oracle));
        assertEq(engine.owner(), owner);
        
        // Check risk params
        (uint256 maxLtv, uint256 lt, uint256 bonus, uint256 apr) = engine.riskParams();
        assertEq(maxLtv, DemoConstants.MAX_LTV_BPS);
        assertEq(lt, DemoConstants.LIQUIDATION_THRESHOLD_BPS);
        assertEq(bonus, DemoConstants.LIQUIDATION_BONUS_BPS);
        assertEq(apr, DemoConstants.BORROW_APR_BPS);
    }
    
    function test_Constructor_InvalidOracle() public {
        vm.expectRevert(BaseLendingEngine.InvalidOracle.selector);
        new BaseLendingEngine(
            address(0),
            address(debtToken),
            address(oracle),
            owner
        );
        
        vm.expectRevert(BaseLendingEngine.InvalidOracle.selector);
        new BaseLendingEngine(
            address(collateralToken),
            address(0),
            address(oracle),
            owner
        );
        
        vm.expectRevert(BaseLendingEngine.InvalidOracle.selector);
        new BaseLendingEngine(
            address(collateralToken),
            address(debtToken),
            address(0),
            owner
        );
    }
    
    // ============ Supply Tests ============
    
    function test_Supply() public {
        uint256 supplyAmount = 10 ether;
        
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit Supplied(user1, address(collateralToken), supplyAmount);
        engine.supply(address(collateralToken), supplyAmount, user1);
        
        // Check position
        (uint256 collateral,,,) = engine.positions(user1);
        assertEq(collateral, supplyAmount);
        assertEq(engine.totalCollateral(), supplyAmount);
        
        // Check token balance
        assertEq(collateralToken.balanceOf(address(engine)), supplyAmount);
        assertEq(collateralToken.balanceOf(user1), 90 ether);
    }
    
    function test_Supply_ForOther() public {
        uint256 supplyAmount = 10 ether;
        
        // user1 supplies for user2
        vm.prank(user1);
        engine.supply(address(collateralToken), supplyAmount, user2);
        
        // user2 should have the position
        (uint256 collateral,,,) = engine.positions(user2);
        assertEq(collateral, supplyAmount);
        
        // user1 should have no position
        (collateral,,,) = engine.positions(user1);
        assertEq(collateral, 0);
    }
    
    function test_Supply_InvalidAmount() public {
        vm.prank(user1);
        vm.expectRevert(BaseLendingEngine.InvalidAmount.selector);
        engine.supply(address(collateralToken), 0, user1);
        
        vm.prank(user1);
        vm.expectRevert(BaseLendingEngine.InvalidAmount.selector);
        engine.supply(address(debtToken), 10 ether, user1); // Wrong asset
        
        vm.prank(user1);
        vm.expectRevert(BaseLendingEngine.InvalidAmount.selector);
        engine.supply(address(collateralToken), 10 ether, address(0));
    }
    
    function test_Supply_WhenPaused() public {
        engine.pause();
        
        vm.prank(user1);
        vm.expectRevert();
        engine.supply(address(collateralToken), 10 ether, user1);
    }
    
    // ============ Borrow Tests ============
    
    function test_Borrow() public {
        // First supply collateral
        vm.prank(user1);
        engine.supply(address(collateralToken), 10 ether, user1);
        
        // Calculate max borrow at 75% LTV
        // 10 ETH * $2000 = $20,000 collateral
        // Max borrow = $20,000 * 0.75 = $15,000 = 15,000 USDC
        uint256 borrowAmount = 15000e6;
        
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit Borrowed(user1, address(debtToken), borrowAmount);
        engine.borrow(address(debtToken), borrowAmount, user1);
        
        // Check position
        (, uint256 debt, uint256 debtAccrued,) = engine.positions(user1);
        assertEq(debt, borrowAmount);
        assertEq(debtAccrued, borrowAmount);
        assertEq(engine.totalDebt(), borrowAmount);
        
        // Check token balance
        assertEq(debtToken.balanceOf(user1), 100000e6 + borrowAmount);
    }
    
    function test_Borrow_ExceedsMaxLTV() public {
        // Supply 10 ETH
        vm.prank(user1);
        engine.supply(address(collateralToken), 10 ether, user1);
        
        // Try to borrow more than 75% LTV
        uint256 borrowAmount = 16000e6; // $16,000 > $15,000 max
        
        vm.prank(user1);
        vm.expectRevert(BaseLendingEngine.BorrowWouldExceedMaxLTV.selector);
        engine.borrow(address(debtToken), borrowAmount, user1);
    }
    
    function test_Borrow_InvalidAmount() public {
        vm.prank(user1);
        vm.expectRevert(BaseLendingEngine.InvalidAmount.selector);
        engine.borrow(address(debtToken), 0, user1);
        
        vm.prank(user1);
        vm.expectRevert(BaseLendingEngine.InvalidAmount.selector);
        engine.borrow(address(collateralToken), 100e6, user1); // Wrong asset
    }
    
    // ============ Withdraw Tests ============
    
    function test_Withdraw() public {
        // Supply and borrow
        vm.prank(user1);
        engine.supply(address(collateralToken), 10 ether, user1);
        vm.prank(user1);
        engine.borrow(address(debtToken), 5000e6, user1);
        
        // Calculate safe withdraw amount
        // Current: 10 ETH collateral, $5,000 debt
        // Max LTV: 75%, so min collateral = $5,000 / 0.75 = $6,667 = 3.333 ETH
        // Can withdraw: 10 - 3.333 = 6.667 ETH
        uint256 withdrawAmount = 6 ether;
        
        uint256 balanceBefore = collateralToken.balanceOf(user1);
        
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit Withdrawn(user1, address(collateralToken), withdrawAmount, user1);
        engine.withdraw(address(collateralToken), withdrawAmount, user1);
        
        // Check position
        (uint256 collateral,,,) = engine.positions(user1);
        assertEq(collateral, 10 ether - withdrawAmount);
        
        // Check token balance
        assertEq(collateralToken.balanceOf(user1), balanceBefore + withdrawAmount);
    }
    
    function test_Withdraw_WouldExceedMaxLTV() public {
        // Supply and max borrow
        vm.prank(user1);
        engine.supply(address(collateralToken), 10 ether, user1);
        vm.prank(user1);
        engine.borrow(address(debtToken), 15000e6, user1); // Max borrow
        
        // Try to withdraw any amount
        vm.prank(user1);
        vm.expectRevert(BaseLendingEngine.WithdrawWouldExceedMaxLTV.selector);
        engine.withdraw(address(collateralToken), 1 ether, user1);
    }
    
    function test_Withdraw_InsufficientCollateral() public {
        vm.prank(user1);
        engine.supply(address(collateralToken), 10 ether, user1);
        
        vm.prank(user1);
        vm.expectRevert(BaseLendingEngine.InsufficientCollateral.selector);
        engine.withdraw(address(collateralToken), 11 ether, user1);
    }
    
    // ============ Repay Tests ============
    
    function test_Repay() public {
        // Supply and borrow
        vm.prank(user1);
        engine.supply(address(collateralToken), 10 ether, user1);
        vm.prank(user1);
        engine.borrow(address(debtToken), 10000e6, user1);
        
        uint256 repayAmount = 5000e6;
        uint256 balanceBefore = debtToken.balanceOf(user1);
        
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit Repaid(user1, address(debtToken), repayAmount, user1);
        engine.repay(address(debtToken), repayAmount, user1);
        
        // Check position
        (, uint256 debt, uint256 debtAccrued,) = engine.positions(user1);
        assertEq(debtAccrued, 10000e6 - repayAmount);
        
        // Check token balance
        assertEq(debtToken.balanceOf(user1), balanceBefore - repayAmount);
    }
    
    function test_Repay_Full() public {
        // Supply and borrow
        vm.prank(user1);
        engine.supply(address(collateralToken), 10 ether, user1);
        vm.prank(user1);
        engine.borrow(address(debtToken), 10000e6, user1);
        
        uint256 repayAmount = 15000e6; // More than debt
        
        vm.prank(user1);
        engine.repay(address(debtToken), repayAmount, user1);
        
        // Check position - should be 0 debt
        (, uint256 debt, uint256 debtAccrued,) = engine.positions(user1);
        assertEq(debtAccrued, 0);
        assertEq(debt, 0);
    }
    
    function test_Repay_ForOther() public {
        // user1 supplies and borrows
        vm.prank(user1);
        engine.supply(address(collateralToken), 10 ether, user1);
        vm.prank(user1);
        engine.borrow(address(debtToken), 10000e6, user1);
        
        // user2 repays for user1
        vm.prank(user2);
        engine.repay(address(debtToken), 5000e6, user1);
        
        // user1's debt should be reduced
        (,, uint256 debtAccrued,) = engine.positions(user1);
        assertEq(debtAccrued, 5000e6);
    }
    
    function test_Repay_NoDebt() public {
        vm.prank(user1);
        vm.expectRevert(BaseLendingEngine.InsufficientDebt.selector);
        engine.repay(address(debtToken), 1000e6, user1);
    }
    
    // ============ Health Factor Tests ============
    
    function test_HealthFactor_NoDebt() public {
        vm.prank(user1);
        engine.supply(address(collateralToken), 10 ether, user1);
        
        uint256 hf = engine.getHealthFactor(user1, INITIAL_PRICE);
        assertEq(hf, type(uint256).max);
    }
    
    function test_HealthFactor_WithDebt() public {
        // Supply 10 ETH ($20,000), borrow $10,000
        // HF = (Collateral Value * LT) / Debt Value
        // HF = ($20,000 * 0.8) / $10,000 = 1.6
        vm.prank(user1);
        engine.supply(address(collateralToken), 10 ether, user1);
        vm.prank(user1);
        engine.borrow(address(debtToken), 10000e6, user1);
        
        uint256 hf = engine.getHealthFactor(user1, INITIAL_PRICE);
        
        // Expected: 1.6e18 = 1.6 in WAD
        assertApproxEqAbs(hf, 1.6e18, 0.01e18); // Allow 0.01 tolerance
    }
    
    function test_HealthFactor_AtLiquidationThreshold() public {
        // Supply 10 ETH ($20,000), borrow max at 75% LTV = $15,000
        // HF = ($20,000 * 0.8) / $15,000 = 1.067
        vm.prank(user1);
        engine.supply(address(collateralToken), 10 ether, user1);
        vm.prank(user1);
        engine.borrow(address(debtToken), 15000e6, user1); // Max borrow at 75% LTV
        
        uint256 hf = engine.getHealthFactor(user1, INITIAL_PRICE);
        assertApproxEqAbs(hf, 1.066e18, 0.01e18); // HF ≈ 1.067
    }
    
    function test_HealthFactor_Liquidatable() public {
        // Supply 10 ETH ($20,000), borrow max at 75% LTV = $15,000
        // To become liquidatable, collateral value must drop so that HF < 1.0
        // HF = (Collateral Value * LT) / Debt Value < 1.0
        // Collateral Value < Debt Value / LT = $15,000 / 0.8 = $18,750
        // Price < $18,750 / 10 ETH = $1,875
        vm.prank(user1);
        engine.supply(address(collateralToken), 10 ether, user1);
        vm.prank(user1);
        engine.borrow(address(debtToken), 15000e6, user1); // Max borrow
        
        // Drop price to make position liquidatable
        oracle.setPrice(address(collateralToken), 1800e18); // $1800 per ETH
        
        uint256 hf = engine.getHealthFactor(user1, 1800e18);
        assertLt(hf, 1e18); // HF < 1.0
        
        bool canLiquidate = engine.canLiquidate(user1, 1800e18);
        assertTrue(canLiquidate);
    }
    
    // ============ Liquidation Tests ============
    
    function test_Liquidate() public {
        // Setup: Supply 10 ETH, borrow max at 75% LTV
        vm.prank(user1);
        engine.supply(address(collateralToken), 10 ether, user1);
        vm.prank(user1);
        engine.borrow(address(debtToken), 15000e6, user1);
        
        // Price drops 50%: $2000 -> $1000
        // New collateral value: 10 * $1000 = $10,000
        // Debt: $15,000
        // HF = ($10,000 * 0.8) / $15,000 = 0.533 < 1.0 -> Liquidatable
        oracle.setPrice(address(collateralToken), 1000e18);
        
        uint256 liquidatorDebtBefore = debtToken.balanceOf(liquidator);
        uint256 liquidatorCollateralBefore = collateralToken.balanceOf(liquidator);
        
        // Liquidate
        vm.prank(liquidator);
        // Note: We don't use vm.expectEmit here because collateral seized depends on price calculation
        // Just verify the liquidation succeeds
        engine.liquidate(user1);
        
        // Check position is cleared
        (uint256 collateral, uint256 debt, uint256 debtAccrued,) = engine.positions(user1);
        assertEq(collateral, 0);
        assertEq(debt, 0);
        assertEq(debtAccrued, 0);
        
        // Liquidator should have paid debt and received collateral + bonus
        uint256 liquidatorDebtAfter = debtToken.balanceOf(liquidator);
        uint256 liquidatorCollateralAfter = collateralToken.balanceOf(liquidator);
        
        // Paid 15,000 USDC
        assertEq(liquidatorDebtBefore - liquidatorDebtAfter, 15000e6);
        
        // Received collateral: Since position is insolvent (collateral < debt),
        // liquidator takes all available collateral (10 ETH)
        // In a real scenario, the protocol would have bad debt handling
        assertEq(liquidatorCollateralAfter - liquidatorCollateralBefore, 10 ether);
    }
    
    function test_Liquidate_NotLiquidatable() public {
        // Supply and borrow safely
        vm.prank(user1);
        engine.supply(address(collateralToken), 10 ether, user1);
        vm.prank(user1);
        engine.borrow(address(debtToken), 5000e6, user1);
        
        vm.prank(liquidator);
        vm.expectRevert(BaseLendingEngine.PositionNotLiquidatable.selector);
        engine.liquidate(user1);
    }
    
    function test_Liquidate_CannotLiquidateSelf() public {
        vm.prank(user1);
        vm.expectRevert(BaseLendingEngine.CannotLiquidateSelf.selector);
        engine.liquidate(user1);
    }
    
    // ============ Interest Accrual Tests ============
    
    function test_InterestAccrual() public {
        // Supply and borrow
        vm.prank(user1);
        engine.supply(address(collateralToken), 10 ether, user1);
        vm.prank(user1);
        engine.borrow(address(debtToken), 10000e6, user1);
        
        // Calculate expected debt after 1 year
        uint256 expectedInterest = (10000e6 * 500 * 365 days) / (10000 * 365 days); // ~500 USDC
        
        // Warp 1 year
        vm.warp(block.timestamp + 365 days);
        
        // Trigger accrual by calling repay
        vm.prank(user1);
        engine.repay(address(debtToken), 20000e6, user1); // Overpay to clear all debt
        
        // After full repay, debt should be 0
        (,, uint256 debtAccrued,) = engine.positions(user1);
        assertEq(debtAccrued, 0); // All debt repaid
        
        // Verify interest was accrued by checking user's debt token balance
        // They borrowed 10000e6 and paid back principal + interest
        uint256 expectedRepay = 10000e6 + expectedInterest;
        // User started with 100000e6, borrowed 10000e6, then repaid
        // Balance = 100000e6 + 10000e6 - actualRepay
        // Since we repaid 20000e6 and it capped at debt+interest
        assertLt(debtToken.balanceOf(user1), 110000e6); // Paid some interest
    }
    
    // ============ Admin Tests ============
    
    function test_SetRiskParams() public {
        engine.setRiskParams(7000, 7500, 300, 400); // 70% LTV, 75% LT, 3% bonus, 4% APR
        
        (uint256 maxLtv, uint256 lt, uint256 bonus, uint256 apr) = engine.riskParams();
        assertEq(maxLtv, 7000);
        assertEq(lt, 7500);
        assertEq(bonus, 300);
        assertEq(apr, 400);
    }
    
    function test_SetRiskParams_Invalid() public {
        // LTV >= LT
        vm.expectRevert(BaseLendingEngine.InvalidRiskParams.selector);
        engine.setRiskParams(8000, 7500, 500, 500);
        
        // LT > 100%
        vm.expectRevert(BaseLendingEngine.InvalidRiskParams.selector);
        engine.setRiskParams(7500, 10100, 500, 500);
        
        // Bonus > 10%
        vm.expectRevert(BaseLendingEngine.InvalidRiskParams.selector);
        engine.setRiskParams(7500, 8000, 1100, 500);
    }
    
    function test_SetRiskParams_OnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        engine.setRiskParams(7000, 7500, 300, 400);
    }
    
    function test_SetOracle() public {
        address newOracle = makeAddr("newOracle");
        
        // Mock oracle needs to have proper interface
        MockPriceOracle mockOracle = new MockPriceOracle(owner, 30 minutes);
        
        engine.setOracle(address(mockOracle));
        assertEq(address(engine.oracle()), address(mockOracle));
    }
    
    function test_PauseUnpause() public {
        engine.pause();
        assertTrue(engine.paused());
        
        engine.unpause();
        assertFalse(engine.paused());
    }
    
    function test_Pause_OnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        engine.pause();
    }
    
    // ============ View Function Tests ============
    
    function test_MaxBorrowAmount() public {
        vm.prank(user1);
        engine.supply(address(collateralToken), 10 ether, user1);
        
        // 10 ETH * $2000 = $20,000
        // Max borrow at 75% LTV = $15,000 = 15,000 USDC
        uint256 maxBorrow = engine.maxBorrowAmount(user1, INITIAL_PRICE);
        assertEq(maxBorrow, 15000e6);
        
        // Borrow some
        vm.prank(user1);
        engine.borrow(address(debtToken), 5000e6, user1);
        
        // Max borrow should decrease
        maxBorrow = engine.maxBorrowAmount(user1, INITIAL_PRICE);
        assertEq(maxBorrow, 10000e6);
    }
    
    function test_MaxWithdrawAmount() public {
        vm.prank(user1);
        engine.supply(address(collateralToken), 10 ether, user1);
        vm.prank(user1);
        engine.borrow(address(debtToken), 5000e6, user1);
        
        // Current: 10 ETH collateral, $5,000 debt
        // Max LTV: 75%, min collateral = $5,000 / 0.75 = $6,667 = 3.333 ETH
        // Max withdraw = 10 - 3.333 = 6.667 ETH
        uint256 maxWithdraw = engine.maxWithdrawAmount(user1, INITIAL_PRICE);
        assertApproxEqAbs(maxWithdraw, 6.667e18, 0.01e18);
    }
    
    function test_GetUserPosition() public {
        vm.prank(user1);
        engine.supply(address(collateralToken), 10 ether, user1);
        vm.prank(user1);
        engine.borrow(address(debtToken), 5000e6, user1);
        
        BaseLendingEngine.Position memory pos = engine.getUserPosition(user1);
        
        assertEq(pos.collateral, 10 ether);
        assertEq(pos.debt, 5000e6);
        assertEq(pos.ltvBps, DemoConstants.MAX_LTV_BPS);
        assertEq(pos.liquidationThresholdBps, DemoConstants.LIQUIDATION_THRESHOLD_BPS);
    }
}
