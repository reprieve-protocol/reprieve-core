// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockPriceOracle} from "../../src/mocks/MockPriceOracle.sol";
import {MockAavePool} from "../../src/mocks/MockAavePool.sol";
import {MockCompoundMarket} from "../../src/mocks/MockCompoundMarket.sol";
import {MockMorphoMarket} from "../../src/mocks/MockMorphoMarket.sol";
import {BaseLendingEngine} from "../../src/mocks/BaseLendingEngine.sol";

contract ProtocolMimicsTest is Test {
    MockERC20 collateral;
    MockERC20 debt;
    MockAavePool aave;
    MockCompoundMarket compound;
    MockMorphoMarket morpho;
    address user;
    address liquidator;
    address minter;
    MockPriceOracle oracle;
    
    function setUp() public {
        user = makeAddr("user");
        liquidator = makeAddr("liquidator");
        minter = makeAddr("minter");
        
        collateral = new MockERC20("WETH", "WETH", 18, minter);
        debt = new MockERC20("USDC", "USDC", 6, minter);
        oracle = new MockPriceOracle(address(this), 30 minutes);
        oracle.setPrice(address(collateral), 2000e18);
        
        aave = new MockAavePool(address(collateral), address(debt), address(oracle), address(this));
        compound = new MockCompoundMarket(address(collateral), address(debt), address(oracle), address(this));
        morpho = new MockMorphoMarket(address(collateral), address(debt), address(oracle), address(this));
        
        // Get engine addresses
        address aaveEngine = address(aave.engine());
        address compoundEngine = address(compound.engine());
        address morphoEngine = address(morpho.engine());
        
        // Mint tokens to user (as minter)
        vm.startPrank(minter);
        collateral.mint(user, 100 ether);
        collateral.mint(liquidator, 100 ether);
        
        // Mint debt tokens to engines so they can lend
        debt.mint(aaveEngine, 1000000e6);
        debt.mint(compoundEngine, 1000000e6);
        debt.mint(morphoEngine, 1000000e6);
        
        // Mint debt tokens to liquidator for liquidations
        debt.mint(liquidator, 1000000e6);
        vm.stopPrank();
    }

    // ============ AAVE TESTS ============
    
    function test_AaveSupply() public {
        vm.startPrank(user);
        collateral.approve(address(aave), type(uint256).max);
        aave.supply(address(collateral), 10 ether, user, 0);
        vm.stopPrank();
        
        BaseLendingEngine.Position memory pos = aave.getUserPosition(user);
        assertEq(pos.collateral, 10 ether);
    }

    function test_AaveSupplyBorrow() public {
        // Supply collateral
        vm.startPrank(user);
        collateral.approve(address(aave), type(uint256).max);
        aave.supply(address(collateral), 10 ether, user, 0);
        
        // Borrow (75% LTV = $15k, price=$2k, 10 WETH = $20k, max borrow $15k)
        aave.borrow(address(debt), 5000e6, 2, 0, user); // 5000 USDC
        vm.stopPrank();
        
        BaseLendingEngine.Position memory pos = aave.getUserPosition(user);
        assertEq(pos.collateral, 10 ether);
        assertEq(pos.debt, 5000e6);
        
        // User should have received USDC
        assertEq(debt.balanceOf(user), 5000e6);
    }
    
    function test_AaveLiquidation() public {
        // Setup position
        vm.startPrank(user);
        collateral.approve(address(aave), type(uint256).max);
        aave.supply(address(collateral), 10 ether, user, 0);
        aave.borrow(address(debt), 15000e6, 2, 0, user); // Max borrow at 75% LTV
        vm.stopPrank();
        
        // Drop price to trigger liquidation (need HF < 1.0, liquidation threshold is 80%)
        // At $2k, 10 WETH = $20k, debt $15k, HF = 20k * 0.8 / 15k = 1.06
        // At $1800, 10 WETH = $18k, HF = 18k * 0.8 / 15k = 0.96 < 1.0
        oracle.setPrice(address(collateral), 1800e18);
        
        // Liquidator repays debt and seizes collateral
        vm.startPrank(liquidator);
        debt.approve(address(aave), type(uint256).max);
        aave.liquidationCall(address(collateral), address(debt), user, 15000e6, false);
        vm.stopPrank();
        
        // Position should be liquidated
        BaseLendingEngine.Position memory pos = aave.getUserPosition(user);
        assertEq(pos.debt, 0);
    }
    
    // ============ COMPOUND TESTS ============
    
    function test_CompoundMint() public {
        vm.startPrank(user);
        collateral.approve(address(compound), type(uint256).max);
        compound.mint(address(collateral), 10 ether);
        vm.stopPrank();
        
        BaseLendingEngine.Position memory pos = compound.getUserPosition(user);
        assertEq(pos.collateral, 10 ether);
    }
    
    function test_CompoundMintBorrow() public {
        vm.startPrank(user);
        collateral.approve(address(compound), type(uint256).max);
        compound.mint(address(collateral), 10 ether);
        compound.borrow(address(debt), 5000e6);
        vm.stopPrank();
        
        BaseLendingEngine.Position memory pos = compound.getUserPosition(user);
        assertEq(pos.collateral, 10 ether);
        assertEq(pos.debt, 5000e6);
        assertEq(debt.balanceOf(user), 5000e6);
    }
    
    function test_CompoundLiquidation() public {
        // Setup position
        vm.startPrank(user);
        collateral.approve(address(compound), type(uint256).max);
        compound.mint(address(collateral), 10 ether);
        compound.borrow(address(debt), 15000e6);
        vm.stopPrank();
        
        // Drop price
        oracle.setPrice(address(collateral), 1800e18);
        
        // Liquidate
        vm.startPrank(liquidator);
        debt.approve(address(compound), type(uint256).max);
        compound.liquidateBorrow(user, 15000e6, address(0));
        vm.stopPrank();
        
        BaseLendingEngine.Position memory pos = compound.getUserPosition(user);
        assertEq(pos.debt, 0);
    }
    
    // ============ MORPHO TESTS ============
    
    function test_MorphoSupplyCollateral() public {
        vm.startPrank(user);
        collateral.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(10 ether, user, "");
        vm.stopPrank();
        
        BaseLendingEngine.Position memory pos = morpho.getUserPosition(user);
        assertEq(pos.collateral, 10 ether);
    }
    
    function test_MorphoSupplyCollateralBorrow() public {
        vm.startPrank(user);
        collateral.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(10 ether, user, "");
        morpho.borrow(5000e6, user, "");
        vm.stopPrank();
        
        BaseLendingEngine.Position memory pos = morpho.getUserPosition(user);
        assertEq(pos.collateral, 10 ether);
        assertEq(pos.debt, 5000e6);
        assertEq(debt.balanceOf(user), 5000e6);
    }
    
    function test_MorphoLiquidation() public {
        // Setup position
        vm.startPrank(user);
        collateral.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(10 ether, user, "");
        morpho.borrow(15000e6, user, "");
        vm.stopPrank();
        
        // Drop price
        oracle.setPrice(address(collateral), 1800e18);
        
        // Liquidate
        vm.startPrank(liquidator);
        debt.approve(address(morpho), type(uint256).max);
        morpho.liquidate(user, 0, "");
        vm.stopPrank();
        
        BaseLendingEngine.Position memory pos = morpho.getUserPosition(user);
        assertEq(pos.debt, 0);
    }
    
    // ============ CROSS-PROTOCOL TESTS ============
    
    function test_AllShareSameEngineLogic() public {
        // All three protocols should have same LTV and liquidation threshold
        assertEq(aave.ltvBps(), compound.ltvBps());
        assertEq(aave.ltvBps(), morpho.ltvBps());
        
        assertEq(aave.liquidationThresholdBps(), compound.liquidationThresholdBps());
        assertEq(aave.liquidationThresholdBps(), morpho.liquidationThresholdBps());
    }
    
    function test_UserCanUseMultipleProtocols() public {
        // User supplies to all three protocols
        vm.startPrank(user);
        
        collateral.approve(address(aave), 10 ether);
        aave.supply(address(collateral), 5 ether, user, 0);
        
        collateral.approve(address(compound), 10 ether);
        compound.mint(address(collateral), 3 ether);
        
        collateral.approve(address(morpho), 10 ether);
        morpho.supplyCollateral(2 ether, user, "");
        
        vm.stopPrank();
        
        // Each protocol should have its own engine with separate positions
        BaseLendingEngine.Position memory aavePos = aave.getUserPosition(user);
        BaseLendingEngine.Position memory compoundPos = compound.getUserPosition(user);
        BaseLendingEngine.Position memory morphoPos = morpho.getUserPosition(user);
        
        assertEq(aavePos.collateral, 5 ether);
        assertEq(compoundPos.collateral, 3 ether);
        assertEq(morphoPos.collateral, 2 ether);
    }
}
