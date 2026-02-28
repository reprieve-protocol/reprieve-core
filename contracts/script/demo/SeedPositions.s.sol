// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {BaseLendingEngine} from "../../src/mocks/BaseLendingEngine.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/**
 * @title SeedPositions
 * @notice Seeding script for Slide 2: Shared Lending Engine
 * @dev Creates deterministic healthy and risky positions for testing
 */
contract SeedPositions is Script {
    
    struct PositionConfig {
        address user;
        uint256 collateralAmount;
        uint256 borrowAmount;
        bool isRisky; // If true, position closer to liquidation
    }
    
    event PositionsSeeded(
        address indexed engine,
        uint256 healthyCount,
        uint256 riskyCount
    );
    
    /**
     * @notice Create a healthy position (low LTV)
     * @param engine BaseLendingEngine address
     * @param user User address
     * @param collateralAmount Collateral to supply
     * @param borrowPercent Percent of max LTV to borrow (e.g., 50 for 50%)
     */
    function createHealthyPosition(
        BaseLendingEngine engine,
        address user,
        uint256 collateralAmount,
        uint256 borrowPercent
    ) internal {
        require(borrowPercent < 75, "Borrow percent must be < 75% for healthy position");
        
        MockERC20 collateral = MockERC20(address(engine.collateralAsset()));
        MockERC20 debt = MockERC20(address(engine.debtAsset()));
        
        // Approve and supply
        vm.startPrank(user);
        collateral.approve(address(engine), collateralAmount);
        engine.supply(address(collateral), collateralAmount, user);
        
        // Calculate borrow amount based on percent of max LTV
        // Max borrow = collateralAmount * price * 0.75 / price = collateralAmount * 0.75
        uint256 maxBorrowCollateralUnits = (collateralAmount * 75) / 100;
        
        // Convert to debt token decimals (assuming 1:1 price for simplicity in seeding)
        uint256 debtDecimals = debt.decimals();
        uint256 collateralDecimals = collateral.decimals();
        uint256 borrowAmount = (maxBorrowCollateralUnits * borrowPercent * (10 ** debtDecimals)) / 
                               (75 * (10 ** collateralDecimals));
        
        if (borrowAmount > 0) {
            // Mint debt tokens to user for borrowing (in real scenario, these come from pool)
            // For testing, we just borrow which transfers from engine
            engine.borrow(address(debt), borrowAmount, user);
        }
        
        vm.stopPrank();
        
        console.log("Created healthy position:");
        console.log("  User:", user);
        console.log("  Collateral:", collateralAmount);
        console.log("  Borrowed:", borrowAmount);
        console.log("  LTV:", borrowPercent, "%");
    }
    
    /**
     * @notice Create a risky position (high LTV, close to liquidation)
     * @param engine BaseLendingEngine address
     * @param user User address
     * @param collateralAmount Collateral to supply
     * @param borrowPercent Percent of max LTV to borrow (e.g., 70 for 70%, close to 75% limit)
     */
    function createRiskyPosition(
        BaseLendingEngine engine,
        address user,
        uint256 collateralAmount,
        uint256 borrowPercent
    ) internal {
        require(borrowPercent >= 70 && borrowPercent < 75, "Borrow percent should be 70-74% for risky position");
        
        MockERC20 collateral = MockERC20(address(engine.collateralAsset()));
        MockERC20 debt = MockERC20(address(engine.debtAsset()));
        
        // Approve and supply
        vm.startPrank(user);
        collateral.approve(address(engine), collateralAmount);
        engine.supply(address(collateral), collateralAmount, user);
        
        // Calculate borrow amount
        uint256 maxBorrowCollateralUnits = (collateralAmount * 75) / 100;
        uint256 debtDecimals = debt.decimals();
        uint256 collateralDecimals = collateral.decimals();
        uint256 borrowAmount = (maxBorrowCollateralUnits * borrowPercent * (10 ** debtDecimals)) / 
                               (75 * (10 ** collateralDecimals));
        
        engine.borrow(address(debt), borrowAmount, user);
        vm.stopPrank();
        
        console.log("Created risky position:");
        console.log("  User:", user);
        console.log("  Collateral:", collateralAmount);
        console.log("  Borrowed:", borrowAmount);
        console.log("  LTV:", borrowPercent, "%");
    }
    
    /**
     * @notice Seed multiple test positions
     * @param engine BaseLendingEngine address
     * @param minter Address that can mint tokens
     */
    function seedTestPositions(address engine, address minter) internal {
        BaseLendingEngine eng = BaseLendingEngine(engine);
        MockERC20 collateral = MockERC20(address(eng.collateralAsset()));
        MockERC20 debt = MockERC20(address(eng.debtAsset()));
        
        console.log("========================================");
        console.log("Seeding Test Positions");
        console.log("========================================");
        
        // Create test users
        address healthyUser1 = makeAddr("healthyUser1");
        address healthyUser2 = makeAddr("healthyUser2");
        address riskyUser1 = makeAddr("riskyUser1");
        address riskyUser2 = makeAddr("riskyUser2");
        address liquidationTarget = makeAddr("liquidationTarget");
        
        uint256 healthyCount = 0;
        uint256 riskyCount = 0;
        
        // Mint collateral to users
        vm.startPrank(minter);
        collateral.mint(healthyUser1, 50 ether);
        collateral.mint(healthyUser2, 30 ether);
        collateral.mint(riskyUser1, 20 ether);
        collateral.mint(riskyUser2, 15 ether);
        collateral.mint(liquidationTarget, 10 ether);
        
        // Mint some debt tokens to engine (simulating liquidity pool)
        debt.mint(address(eng), 1000000e6);
        vm.stopPrank();
        
        // Create healthy positions (50% LTV)
        createHealthyPosition(eng, healthyUser1, 50 ether, 50);
        healthyCount++;
        
        createHealthyPosition(eng, healthyUser2, 30 ether, 40);
        healthyCount++;
        
        // Create risky positions (73% LTV - close to 75% limit)
        createRiskyPosition(eng, riskyUser1, 20 ether, 73);
        riskyCount++;
        
        createRiskyPosition(eng, riskyUser2, 15 ether, 72);
        riskyCount++;
        
        // Create a position for liquidation testing (74% LTV, will be liquidated after price drop)
        createRiskyPosition(eng, liquidationTarget, 10 ether, 74);
        riskyCount++;
        
        emit PositionsSeeded(engine, healthyCount, riskyCount);
        
        console.log("========================================");
        console.log("Seeding Complete");
        console.log("  Healthy positions:", healthyCount);
        console.log("  Risky positions:", riskyCount);
        console.log("========================================");
    }
    
    /**
     * @notice Run seeding
     */
    function run() external {
        address engine = vm.envOr("ENGINE_ADDRESS", address(0));
        address minter = vm.envOr("MINTER_ADDRESS", msg.sender);
        
        require(engine != address(0), "ENGINE_ADDRESS not set");
        
        seedTestPositions(engine, minter);
    }
    
    /**
     * @notice Run with explicit parameters
     * @param engine BaseLendingEngine address
     * @param minter Minter address for tokens
     */
    function runExplicit(address engine, address minter) external {
        require(engine != address(0), "Invalid engine address");
        require(minter != address(0), "Invalid minter address");
        
        seedTestPositions(engine, minter);
    }
    
    /**
     * @notice Create a single position for testing
     * @param engine BaseLendingEngine address
     * @param minter Minter address
     * @param user User address
     * @param collateralAmount Collateral amount
     * @param borrowAmount Borrow amount
     */
    function createSinglePosition(
        address engine,
        address minter,
        address user,
        uint256 collateralAmount,
        uint256 borrowAmount
    ) external {
        BaseLendingEngine eng = BaseLendingEngine(engine);
        MockERC20 collateral = MockERC20(address(eng.collateralAsset()));
        MockERC20 debt = MockERC20(address(eng.debtAsset()));
        
        // Mint tokens
        vm.startPrank(minter);
        collateral.mint(user, collateralAmount);
        debt.mint(address(eng), borrowAmount * 10); // Ensure engine has liquidity
        vm.stopPrank();
        
        // Create position
        vm.startPrank(user);
        collateral.approve(address(eng), collateralAmount);
        eng.supply(address(collateral), collateralAmount, user);
        if (borrowAmount > 0) {
            eng.borrow(address(debt), borrowAmount, user);
        }
        vm.stopPrank();
        
        console.log("Single position created:");
        console.log("  User:", user);
        console.log("  Collateral:", collateralAmount);
        console.log("  Borrowed:", borrowAmount);
    }
}
