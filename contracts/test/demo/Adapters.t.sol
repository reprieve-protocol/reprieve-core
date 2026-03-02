// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockPriceOracle} from "../../src/mocks/MockPriceOracle.sol";
import {MockAavePool} from "../../src/mocks/MockAavePool.sol";
import {MockCompoundMarket} from "../../src/mocks/MockCompoundMarket.sol";
import {MockMorphoMarket} from "../../src/mocks/MockMorphoMarket.sol";
import {BaseLendingEngine} from "../../src/mocks/BaseLendingEngine.sol";
import {AaveLikeAdapter} from "../../src/adapters/AaveLikeAdapter.sol";
import {CompoundLikeAdapter} from "../../src/adapters/CompoundLikeAdapter.sol";
import {MorphoLikeAdapter} from "../../src/adapters/MorphoLikeAdapter.sol";
import {IReprieveAdapter} from "../../src/interfaces/IReprieveAdapter.sol";
import {BaseAdapter} from "../../src/adapters/BaseAdapter.sol";

contract AdaptersTest is Test {
    // Events from IReprieveAdapter for testing
    event DebtRepaid(address indexed user, address indexed asset, uint256 amount);
    event CollateralWithdrawn(address indexed user, address indexed asset, uint256 amount, address indexed to);
    event CollateralSupplied(address indexed user, address indexed asset, uint256 amount);
    // Tokens
    MockERC20 collateral;
    MockERC20 debt;
    
    // Oracle
    MockPriceOracle oracle;
    
    // Protocols
    MockAavePool aavePool;
    MockCompoundMarket compoundMarket;
    MockMorphoMarket morphoMarket;
    
    // Adapters
    AaveLikeAdapter aaveAdapter;
    CompoundLikeAdapter compoundAdapter;
    MorphoLikeAdapter morphoAdapter;
    
    // Test addresses
    address user;
    address rescuer;
    address minter;
    address owner;
    
    function setUp() public {
        user = makeAddr("user");
        rescuer = makeAddr("rescuer");
        minter = makeAddr("minter");
        owner = address(this);
        
        // Deploy tokens
        collateral = new MockERC20("WETH", "WETH", 18, minter);
        debt = new MockERC20("USDC", "USDC", 6, minter);
        
        // Deploy oracle
        oracle = new MockPriceOracle(owner, 30 minutes);
        oracle.setPrice(address(collateral), 2000e18);
        
        // Deploy protocols
        aavePool = new MockAavePool(address(collateral), address(debt), address(oracle), owner);
        compoundMarket = new MockCompoundMarket(address(collateral), address(debt), address(oracle), owner);
        morphoMarket = new MockMorphoMarket(address(collateral), address(debt), address(oracle), owner);
        
        // Deploy adapters
        aaveAdapter = new AaveLikeAdapter(
            address(aavePool),
            address(collateral),
            address(debt),
            owner
        );
        
        compoundAdapter = new CompoundLikeAdapter(
            address(compoundMarket),
            address(collateral),
            address(debt),
            address(compoundMarket.cToken()),
            owner
        );
        
        morphoAdapter = new MorphoLikeAdapter(
            address(morphoMarket),
            address(collateral),
            address(debt),
            keccak256("TEST_MARKET"),
            owner
        );
        
        // Mint tokens to engines for lending
        vm.startPrank(minter);
        debt.mint(address(aavePool.engine()), 1000000e6);
        debt.mint(address(compoundMarket.engine()), 1000000e6);
        debt.mint(address(morphoMarket.engine()), 1000000e6);
        
        // Mint tokens to user and rescuer
        collateral.mint(user, 100 ether);
        collateral.mint(rescuer, 100 ether);
        debt.mint(rescuer, 1000000e6);
        vm.stopPrank();
    }
    
    // ============ INTERFACE CONFORMANCE TESTS ============
    
    function test_AaveAdapter_ProtocolName() public view {
        assertEq(aaveAdapter.protocolName(), "AaveV3");
    }
    
    function test_CompoundAdapter_ProtocolName() public view {
        assertEq(compoundAdapter.protocolName(), "CompoundV2");
    }
    
    function test_MorphoAdapter_ProtocolName() public view {
        assertEq(morphoAdapter.protocolName(), "MorphoBlue");
    }
    
    function test_Adapters_ProtocolAddress() public view {
        assertEq(aaveAdapter.protocolAddress(), address(aavePool));
        assertEq(compoundAdapter.protocolAddress(), address(compoundMarket));
        assertEq(morphoAdapter.protocolAddress(), address(morphoMarket));
    }
    
    function test_Adapters_SupportsPair() public view {
        // Should support correct pair
        assertTrue(aaveAdapter.supportsPair(address(collateral), address(debt)));
        assertTrue(compoundAdapter.supportsPair(address(collateral), address(debt)));
        assertTrue(morphoAdapter.supportsPair(address(collateral), address(debt)));
        
        // Should not support wrong pairs
        assertFalse(aaveAdapter.supportsPair(address(debt), address(collateral)));
        assertFalse(aaveAdapter.supportsPair(address(0), address(debt)));
    }
    
    // ============ POSITION DISCOVERY TESTS ============
    
    function test_AaveAdapter_DiscoverPositions() public {
        // Setup position
        vm.startPrank(user);
        collateral.approve(address(aavePool), type(uint256).max);
        aavePool.supply(address(collateral), 10 ether, user, 0);
        aavePool.borrow(address(debt), 5000e6, 2, 0, user);
        vm.stopPrank();
        
        IReprieveAdapter.Position[] memory positions = aaveAdapter.discoverPositions(user);
        
        assertEq(positions.length, 1);
        assertEq(positions[0].collateralAmount, 10 ether);
        assertEq(positions[0].debtAmount, 5000e6);
        assertEq(positions[0].protocol, address(aavePool));
    }
    
    function test_CompoundAdapter_DiscoverPositions() public {
        // Setup position
        vm.startPrank(user);
        collateral.approve(address(compoundMarket), type(uint256).max);
        compoundMarket.mint(address(collateral), 10 ether);
        compoundMarket.borrow(address(debt), 5000e6);
        vm.stopPrank();
        
        IReprieveAdapter.Position[] memory positions = compoundAdapter.discoverPositions(user);
        
        assertEq(positions.length, 1);
        assertEq(positions[0].collateralAmount, 10 ether);
        assertEq(positions[0].debtAmount, 5000e6);
    }
    
    function test_MorphoAdapter_DiscoverPositions() public {
        // Setup position
        vm.startPrank(user);
        collateral.approve(address(morphoMarket), type(uint256).max);
        morphoMarket.supplyCollateral(10 ether, user, "");
        morphoMarket.borrow(5000e6, user, "");
        vm.stopPrank();
        
        IReprieveAdapter.Position[] memory positions = morphoAdapter.discoverPositions(user);
        
        assertEq(positions.length, 1);
        assertEq(positions[0].collateralAmount, 10 ether);
        assertEq(positions[0].debtAmount, 5000e6);
    }
    
    function test_Adapter_DiscoverPositions_Empty() public view {
        // User with no positions should return empty array
        IReprieveAdapter.Position[] memory positions = aaveAdapter.discoverPositions(user);
        assertEq(positions.length, 0);
    }
    
    // ============ HEALTH FACTOR TESTS ============
    
    function test_Adapters_HealthFactor() public {
        // Setup position
        vm.startPrank(user);
        collateral.approve(address(aavePool), type(uint256).max);
        aavePool.supply(address(collateral), 10 ether, user, 0);
        aavePool.borrow(address(debt), 5000e6, 2, 0, user);
        vm.stopPrank();
        
        uint256 hf = aaveAdapter.healthFactor(user);
        // HF should be healthy (> 1.0)
        assertGt(hf, 1e18);
    }
    
    // ============ AVAILABLE COLLATERAL TESTS ============
    
    function test_AaveAdapter_AvailableCollateral() public {
        vm.startPrank(user);
        collateral.approve(address(aavePool), type(uint256).max);
        aavePool.supply(address(collateral), 10 ether, user, 0);
        vm.stopPrank();
        
        // With no debt, all collateral should be available
        uint256 available = aaveAdapter.availableCollateral(user, address(collateral));
        assertEq(available, 10 ether);
    }
    
    function test_AaveAdapter_AvailableCollateral_WithDebt() public {
        vm.startPrank(user);
        collateral.approve(address(aavePool), type(uint256).max);
        aavePool.supply(address(collateral), 10 ether, user, 0);
        aavePool.borrow(address(debt), 10000e6, 2, 0, user); // 50% LTV
        vm.stopPrank();
        
        // With debt, available should be limited
        uint256 available = aaveAdapter.availableCollateral(user, address(collateral));
        // Should be less than 10 ether but greater than 0
        assertLt(available, 10 ether);
        assertGt(available, 0);
    }
    
    function test_Adapter_AvailableCollateral_UnsupportedAsset() public {
        vm.expectRevert(BaseAdapter.UnsupportedAsset.selector);
        aaveAdapter.availableCollateral(user, address(0));
    }
    
    // ============ GET DEBT TESTS ============
    
    function test_Adapters_GetDebt() public {
        vm.startPrank(user);
        collateral.approve(address(aavePool), type(uint256).max);
        aavePool.supply(address(collateral), 10 ether, user, 0);
        aavePool.borrow(address(debt), 5000e6, 2, 0, user);
        vm.stopPrank();
        
        uint256 debtAmount = aaveAdapter.getDebt(user, address(debt));
        assertEq(debtAmount, 5000e6);
    }
    
    // ============ RESCUE ACTION TESTS ============
    
    function test_AaveAdapter_RepayForRescue() public {
        // Setup position
        vm.startPrank(user);
        collateral.approve(address(aavePool), type(uint256).max);
        aavePool.supply(address(collateral), 10 ether, user, 0);
        aavePool.borrow(address(debt), 5000e6, 2, 0, user);
        vm.stopPrank();
        
        uint256 debtBefore = aavePool.getUserPosition(user).debt;
        
        // Rescuer repays debt
        vm.startPrank(rescuer);
        debt.approve(address(aaveAdapter), type(uint256).max);
        aaveAdapter.repayForRescue(user, address(debt), 2000e6);
        vm.stopPrank();
        
        uint256 debtAfter = aavePool.getUserPosition(user).debt;
        assertEq(debtBefore - debtAfter, 2000e6);
    }
    
    function test_AaveAdapter_RepayForRescue_EmitsEvent() public {
        vm.startPrank(user);
        collateral.approve(address(aavePool), type(uint256).max);
        aavePool.supply(address(collateral), 10 ether, user, 0);
        aavePool.borrow(address(debt), 5000e6, 2, 0, user);
        vm.stopPrank();
        
        vm.startPrank(rescuer);
        debt.approve(address(aaveAdapter), type(uint256).max);
        
        vm.expectEmit(true, true, false, true, address(aaveAdapter));
        emit DebtRepaid(user, address(debt), 2000e6);
        
        aaveAdapter.repayForRescue(user, address(debt), 2000e6);
        vm.stopPrank();
    }

    function test_AaveAdapter_SupplyForRescue() public {
        uint256 collateralBefore = aavePool.getUserPosition(user).collateral;

        vm.startPrank(rescuer);
        collateral.approve(address(aaveAdapter), type(uint256).max);
        aaveAdapter.supplyForRescue(user, address(collateral), 2 ether);
        vm.stopPrank();

        uint256 collateralAfter = aavePool.getUserPosition(user).collateral;
        assertEq(collateralAfter - collateralBefore, 2 ether);
    }

    function test_CompoundAdapter_SupplyForRescue() public {
        uint256 collateralBefore = compoundMarket.getUserPosition(user).collateral;

        vm.startPrank(rescuer);
        collateral.approve(address(compoundAdapter), type(uint256).max);
        compoundAdapter.supplyForRescue(user, address(collateral), 3 ether);
        vm.stopPrank();

        uint256 collateralAfter = compoundMarket.getUserPosition(user).collateral;
        assertEq(collateralAfter - collateralBefore, 3 ether);
    }

    function test_MorphoAdapter_SupplyForRescue() public {
        uint256 collateralBefore = morphoMarket.getUserPosition(user).collateral;

        vm.startPrank(rescuer);
        collateral.approve(address(morphoAdapter), type(uint256).max);
        morphoAdapter.supplyForRescue(user, address(collateral), 1 ether);
        vm.stopPrank();

        uint256 collateralAfter = morphoMarket.getUserPosition(user).collateral;
        assertEq(collateralAfter - collateralBefore, 1 ether);
    }
    
    // ============ PAUSE TESTS ============
    
    function test_Adapter_Pause() public {
        aaveAdapter.pause();
        assertTrue(aaveAdapter.paused());
    }
    
    function test_Adapter_Unpause() public {
        aaveAdapter.pause();
        aaveAdapter.unpause();
        assertFalse(aaveAdapter.paused());
    }
    
    function test_Adapter_RevertWhenPaused() public {
        aaveAdapter.pause();
        
        vm.expectRevert(BaseAdapter.AdapterPaused.selector);
        aaveAdapter.repayForRescue(user, address(debt), 1000e6);
    }
    
    function test_Adapter_Repay_UnsupportedAsset() public {
        vm.expectRevert(BaseAdapter.UnsupportedAsset.selector);
        aaveAdapter.repayForRescue(user, address(0), 1000e6);
    }

    function test_Adapter_Supply_UnsupportedAsset() public {
        vm.expectRevert(BaseAdapter.UnsupportedAsset.selector);
        aaveAdapter.supplyForRescue(user, address(debt), 1 ether);
    }

    function test_Adapter_Supply_ZeroAmount() public {
        vm.expectRevert(BaseAdapter.ZeroAmount.selector);
        aaveAdapter.supplyForRescue(user, address(collateral), 0);
    }
    
    function test_Adapter_OnlyOwnerCanPause() public {
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert();
        aaveAdapter.pause();
    }
    
    // ============ CROSS-ADAPTER CONSISTENCY TESTS ============
    
    function test_AllAdapters_SamePositionData() public {
        // Setup same position in all protocols
        vm.startPrank(user);
        
        collateral.approve(address(aavePool), 10 ether);
        aavePool.supply(address(collateral), 10 ether, user, 0);
        aavePool.borrow(address(debt), 5000e6, 2, 0, user);
        
        collateral.approve(address(compoundMarket), 10 ether);
        compoundMarket.mint(address(collateral), 10 ether);
        compoundMarket.borrow(address(debt), 5000e6);
        
        collateral.approve(address(morphoMarket), 10 ether);
        morphoMarket.supplyCollateral(10 ether, user, "");
        morphoMarket.borrow(5000e6, user, "");
        
        vm.stopPrank();
        
        // All adapters should report same position
        IReprieveAdapter.Position[] memory aavePos = aaveAdapter.discoverPositions(user);
        IReprieveAdapter.Position[] memory compoundPos = compoundAdapter.discoverPositions(user);
        IReprieveAdapter.Position[] memory morphoPos = morphoAdapter.discoverPositions(user);
        
        assertEq(aavePos[0].collateralAmount, compoundPos[0].collateralAmount);
        assertEq(aavePos[0].collateralAmount, morphoPos[0].collateralAmount);
        assertEq(aavePos[0].debtAmount, compoundPos[0].debtAmount);
        assertEq(aavePos[0].debtAmount, morphoPos[0].debtAmount);
    }
    
    function test_AllAdapters_SameHealthFactor() public {
        // Setup same position in all protocols
        vm.startPrank(user);
        
        collateral.approve(address(aavePool), 10 ether);
        aavePool.supply(address(collateral), 10 ether, user, 0);
        aavePool.borrow(address(debt), 5000e6, 2, 0, user);
        
        collateral.approve(address(compoundMarket), 10 ether);
        compoundMarket.mint(address(collateral), 10 ether);
        compoundMarket.borrow(address(debt), 5000e6);
        
        collateral.approve(address(morphoMarket), 10 ether);
        morphoMarket.supplyCollateral(10 ether, user, "");
        morphoMarket.borrow(5000e6, user, "");
        
        vm.stopPrank();
        
        // Health factors should be similar (same underlying engine)
        uint256 aaveHF = aaveAdapter.healthFactor(user);
        uint256 compoundHF = compoundAdapter.healthFactor(user);
        uint256 morphoHF = morphoAdapter.healthFactor(user);
        
        // All should be healthy
        assertGt(aaveHF, 1e18);
        assertGt(compoundHF, 1e18);
        assertGt(morphoHF, 1e18);
    }
}
