// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockPriceOracle} from "../../src/mocks/MockPriceOracle.sol";
import {DemoConstants} from "../../src/libs/DemoConstants.sol";

/**
 * @title PrimitivesTest
 * @notice Tests for Slide 1: Core Primitives (ERC20 + Oracle)
 * @dev Tests MockERC20 and MockPriceOracle functionality
 */
contract PrimitivesTest is Test {
    MockERC20 public collateralToken;
    MockERC20 public debtToken;
    MockPriceOracle public oracle;
    
    address public owner;
    address public minter;
    address public user1;
    address public user2;
    address public authorizedUpdater;
    
    // Events for testing
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);
    event MinterUpdated(address indexed newMinter);
    event AdminUpdated(address indexed newAdmin);
    event BridgeBurnerSet(address indexed account, bool allowed);
    event BridgeMinterSet(address indexed account, bool allowed);
    event BridgeBurn(address indexed burner, address indexed from, uint256 amount);
    event BridgeMint(address indexed minter, address indexed to, uint256 amount);
    event PriceUpdated(address indexed asset, uint256 price, uint256 timestamp);
    event PriceSet(
        address indexed asset,
        uint256 price,
        uint256 timestamp,
        uint256 blockNumber,
        address indexed updater
    );
    event AuthorizedUpdaterSet(address indexed updater, bool authorized);
    event OracleStatusSet(bool isActive);
    event StalenessThresholdUpdated(uint256 threshold);
    
    function setUp() public {
        owner = address(this);
        minter = makeAddr("minter");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        authorizedUpdater = makeAddr("authorizedUpdater");
        
        // Deploy tokens
        collateralToken = new MockERC20("Wrapped Ether", "WETH", 18, minter);
        debtToken = new MockERC20("USD Coin", "USDC", 6, minter);
        
        // Deploy oracle with 30 minute staleness threshold
        oracle = new MockPriceOracle(owner, 30 minutes);
    }
    
    // ============ MockERC20 Tests ============
    
    function test_ERC20_Metadata() public view {
        assertEq(collateralToken.name(), "Wrapped Ether");
        assertEq(collateralToken.symbol(), "WETH");
        assertEq(collateralToken.decimals(), 18);
        
        assertEq(debtToken.name(), "USD Coin");
        assertEq(debtToken.symbol(), "USDC");
        assertEq(debtToken.decimals(), 6);
    }
    
    function test_ERC20_Mint() public {
        uint256 mintAmount = 1000 ether;
        
        vm.prank(minter);
        vm.expectEmit(true, false, false, true);
        emit Mint(user1, mintAmount);
        collateralToken.mint(user1, mintAmount);
        
        assertEq(collateralToken.balanceOf(user1), mintAmount);
        assertEq(collateralToken.totalSupply(), mintAmount);
    }
    
    function test_ERC20_Mint_OnlyMinter() public {
        vm.prank(user1);
        vm.expectRevert("MockERC20: caller is not minter");
        collateralToken.mint(user1, 100 ether);
    }
    
    function test_ERC20_Mint_ZeroAddress() public {
        vm.prank(minter);
        vm.expectRevert("MockERC20: mint to zero address");
        collateralToken.mint(address(0), 100 ether);
    }
    
    function test_ERC20_Mint_ZeroAmount() public {
        vm.prank(minter);
        vm.expectRevert("MockERC20: mint amount must be > 0");
        collateralToken.mint(user1, 0);
    }
    
    function test_ERC20_Burn() public {
        uint256 mintAmount = 1000 ether;
        uint256 burnAmount = 500 ether;
        
        vm.prank(minter);
        collateralToken.mint(user1, mintAmount);
        
        vm.prank(minter);
        vm.expectEmit(true, false, false, true);
        emit Burn(user1, burnAmount);
        collateralToken.burn(user1, burnAmount);
        
        assertEq(collateralToken.balanceOf(user1), mintAmount - burnAmount);
        assertEq(collateralToken.totalSupply(), mintAmount - burnAmount);
    }
    
    function test_ERC20_Burn_ExceedsBalance() public {
        vm.prank(minter);
        collateralToken.mint(user1, 100 ether);
        
        vm.prank(minter);
        vm.expectRevert("MockERC20: burn amount exceeds balance");
        collateralToken.burn(user1, 200 ether);
    }
    
    function test_ERC20_BatchMint() public {
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;
        
        vm.prank(minter);
        collateralToken.batchMint(recipients, amounts);
        
        assertEq(collateralToken.balanceOf(user1), 100 ether);
        assertEq(collateralToken.balanceOf(user2), 200 ether);
        assertEq(collateralToken.totalSupply(), 300 ether);
    }
    
    function test_ERC20_SetMinter() public {
        address newMinter = makeAddr("newMinter");
        
        vm.prank(minter);
        vm.expectEmit(true, false, false, false);
        emit MinterUpdated(newMinter);
        collateralToken.setMinter(newMinter);
        
        assertEq(collateralToken.minter(), newMinter);
        
        // New minter can mint
        vm.prank(newMinter);
        collateralToken.mint(user1, 100 ether);
        
        // Old minter cannot
        vm.prank(minter);
        vm.expectRevert("MockERC20: caller is not minter");
        collateralToken.mint(user1, 100 ether);
    }

    function test_ERC20_SetAdmin() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(minter);
        vm.expectEmit(true, false, false, false);
        emit AdminUpdated(newAdmin);
        collateralToken.setAdmin(newAdmin);

        assertEq(collateralToken.admin(), newAdmin);
    }

    function test_ERC20_SetBridgeRoles_OnlyAdmin() public {
        vm.prank(user1);
        vm.expectRevert("MockERC20: caller is not admin");
        collateralToken.setBridgeBurner(user2, true);

        vm.prank(user1);
        vm.expectRevert("MockERC20: caller is not admin");
        collateralToken.setBridgeMinter(user2, true);
    }

    function test_ERC20_BridgeBurnAndMint() public {
        address bridge = makeAddr("bridge");

        vm.prank(minter);
        collateralToken.setBridgeBurner(bridge, true);
        vm.prank(minter);
        collateralToken.setBridgeMinter(bridge, true);

        vm.prank(minter);
        collateralToken.mint(user1, 100 ether);
        assertEq(collateralToken.totalSupply(), 100 ether);

        vm.prank(bridge);
        vm.expectEmit(true, true, false, true);
        emit BridgeBurn(bridge, user1, 30 ether);
        collateralToken.bridgeBurn(user1, 30 ether);

        assertEq(collateralToken.balanceOf(user1), 70 ether);
        assertEq(collateralToken.totalSupply(), 70 ether);

        vm.prank(bridge);
        vm.expectEmit(true, true, false, true);
        emit BridgeMint(bridge, user2, 30 ether);
        collateralToken.bridgeMint(user2, 30 ether);

        assertEq(collateralToken.balanceOf(user2), 30 ether);
        assertEq(collateralToken.totalSupply(), 100 ether);
    }

    function test_ERC20_BridgeBurn_UnauthorizedReverts() public {
        vm.prank(minter);
        collateralToken.mint(user1, 10 ether);

        vm.prank(user2);
        vm.expectRevert("MockERC20: caller is not bridge burner");
        collateralToken.bridgeBurn(user1, 1 ether);
    }

    function test_ERC20_BridgeMint_UnauthorizedReverts() public {
        vm.prank(user2);
        vm.expectRevert("MockERC20: caller is not bridge minter");
        collateralToken.bridgeMint(user1, 1 ether);
    }
    
    function test_ERC20_TransferAndAllowance() public {
        uint256 amount = 1000 ether;
        
        vm.prank(minter);
        collateralToken.mint(user1, amount);
        
        // Transfer
        vm.prank(user1);
        assertTrue(collateralToken.transfer(user2, 300 ether));
        assertEq(collateralToken.balanceOf(user1), 700 ether);
        assertEq(collateralToken.balanceOf(user2), 300 ether);
        
        // Approve and transferFrom
        vm.prank(user2);
        collateralToken.approve(user1, 200 ether);
        assertEq(collateralToken.allowance(user2, user1), 200 ether);
        
        vm.prank(user1);
        collateralToken.transferFrom(user2, user1, 150 ether);
        assertEq(collateralToken.balanceOf(user1), 850 ether);
        assertEq(collateralToken.balanceOf(user2), 150 ether);
        assertEq(collateralToken.allowance(user2, user1), 50 ether);
    }
    
    function test_ERC20_Allowance_Exceeds() public {
        vm.prank(minter);
        collateralToken.mint(user2, 100 ether);
        
        vm.prank(user2);
        collateralToken.approve(user1, 50 ether);
        
        vm.prank(user1);
        vm.expectRevert();
        collateralToken.transferFrom(user2, user1, 100 ether);
    }
    
    function test_ERC20_TotalMinted() public {
        vm.prank(minter);
        collateralToken.mint(user1, 500 ether);
        
        assertEq(collateralToken.totalMinted(), 500 ether);
        assertEq(collateralToken.totalMinted(), collateralToken.totalSupply());
    }
    
    // ============ MockPriceOracle Tests ============
    
    function test_Oracle_InitialState() public view {
        assertEq(oracle.stalenessThreshold(), 30 minutes);
        assertTrue(oracle.isActive());
        assertEq(oracle.owner(), owner);
    }
    
    function test_Oracle_SetPrice() public {
        uint256 price = 2000e18; // $2000 in WAD
        
        vm.expectEmit(true, false, false, false);
        emit PriceUpdated(address(collateralToken), price, block.timestamp);
        oracle.setPrice(address(collateralToken), price);
        
        (uint256 storedPrice, uint256 timestamp) = oracle.getPrice(address(collateralToken));
        assertEq(storedPrice, price);
        assertEq(timestamp, block.timestamp);
    }
    
    function test_Oracle_SetPrice_OnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        oracle.setPrice(address(collateralToken), 2000e18);
    }
    
    function test_Oracle_SetPrice_ZeroAddress() public {
        vm.expectRevert("MockPriceOracle: asset cannot be zero address");
        oracle.setPrice(address(0), 2000e18);
    }
    
    function test_Oracle_SetPrice_MinMaxBounds() public {
        // Below minimum
        vm.expectRevert("MockPriceOracle: price below minimum");
        oracle.setPrice(address(collateralToken), 1e7); // Below MIN_PRICE
        
        // Above maximum
        vm.expectRevert("MockPriceOracle: price above maximum");
        oracle.setPrice(address(collateralToken), 1e31); // Above MAX_PRICE
        
        // Valid minimum edge
        oracle.setPrice(address(collateralToken), 1e8);
        
        // Valid maximum edge
        oracle.setPrice(address(debtToken), 1e30);
    }
    
    function test_Oracle_SetPrice_WhenPaused() public {
        oracle.setActive(false);
        
        vm.expectRevert("MockPriceOracle: oracle is paused");
        oracle.setPrice(address(collateralToken), 2000e18);
    }
    
    function test_Oracle_GetLatestPrice() public {
        uint256 price = 2000e18;
        oracle.setPrice(address(collateralToken), price);
        
        uint256 latestPrice = oracle.getLatestPrice(address(collateralToken));
        assertEq(latestPrice, price);
    }
    
    function test_Oracle_GetLatestPrice_NotSet() public {
        vm.expectRevert("MockPriceOracle: price not set for asset");
        oracle.getLatestPrice(address(collateralToken));
    }
    
    function test_Oracle_GetLatestPrice_Stale() public {
        oracle.setPrice(address(collateralToken), 2000e18);
        
        // Warp past staleness threshold
        vm.warp(block.timestamp + 31 minutes);
        
        vm.expectRevert("MockPriceOracle: price is stale");
        oracle.getLatestPrice(address(collateralToken));
    }
    
    function test_Oracle_IsStale() public {
        // Initially stale (never set)
        assertTrue(oracle.isStale(address(collateralToken)));
        
        // Set price
        oracle.setPrice(address(collateralToken), 2000e18);
        assertFalse(oracle.isStale(address(collateralToken)));
        
        // Warp to just before threshold
        vm.warp(block.timestamp + 29 minutes);
        assertFalse(oracle.isStale(address(collateralToken)));
        
        // Warp past threshold
        vm.warp(block.timestamp + 2 minutes); // Now 31 minutes total
        assertTrue(oracle.isStale(address(collateralToken)));
    }
    
    function test_Oracle_TimeSinceUpdate() public {
        // Never updated
        assertEq(oracle.timeSinceUpdate(address(collateralToken)), type(uint256).max);
        
        // Set price
        uint256 setTime = block.timestamp;
        oracle.setPrice(address(collateralToken), 2000e18);
        assertEq(oracle.timeSinceUpdate(address(collateralToken)), 0);
        
        // Warp forward
        vm.warp(setTime + 5 minutes);
        assertEq(oracle.timeSinceUpdate(address(collateralToken)), 5 minutes);
    }
    
    function test_Oracle_BatchSetPrices() public {
        address[] memory assets = new address[](2);
        assets[0] = address(collateralToken);
        assets[1] = address(debtToken);
        
        uint256[] memory prices = new uint256[](2);
        prices[0] = 2000e18; // WETH = $2000
        prices[1] = 1e18;    // USDC = $1
        
        oracle.batchSetPrices(assets, prices);
        
        assertEq(oracle.getLatestPrice(address(collateralToken)), 2000e18);
        assertEq(oracle.getLatestPrice(address(debtToken)), 1e18);
    }
    
    function test_Oracle_AuthorizedUpdater() public {
        oracle.setAuthorizedUpdater(authorizedUpdater, true);
        
        // Authorized updater can set price
        vm.prank(authorizedUpdater);
        oracle.setPrice(address(collateralToken), 2000e18);
        
        // Non-authorized cannot
        vm.prank(user1);
        vm.expectRevert();
        oracle.setPrice(address(collateralToken), 2000e18);
    }
    
    function test_Oracle_SetAuthorizedUpdater_OnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        oracle.setAuthorizedUpdater(authorizedUpdater, true);
    }
    
    function test_Oracle_SetStalenessThreshold() public {
        vm.expectEmit(false, false, false, true);
        emit StalenessThresholdUpdated(1 hours);
        oracle.setStalenessThreshold(1 hours);
        
        assertEq(oracle.stalenessThreshold(), 1 hours);
    }
    
    function test_Oracle_SetStalenessThreshold_Zero() public {
        vm.expectRevert("MockPriceOracle: threshold must be > 0");
        oracle.setStalenessThreshold(0);
    }
    
    function test_Oracle_SetActive() public {
        vm.expectEmit(false, false, false, true);
        emit OracleStatusSet(false);
        oracle.setActive(false);
        
        assertFalse(oracle.isActive());
        
        oracle.setActive(true);
        assertTrue(oracle.isActive());
    }
    
    function test_Oracle_HasPrice() public {
        assertFalse(oracle.hasPrice(address(collateralToken)));
        
        oracle.setPrice(address(collateralToken), 2000e18);
        assertTrue(oracle.hasPrice(address(collateralToken)));
    }
    
    function test_Oracle_GetLastUpdateBlock() public {
        uint256 blockNum = block.number;
        oracle.setPrice(address(collateralToken), 2000e18);
        
        assertEq(oracle.getLastUpdateBlock(address(collateralToken)), blockNum);
    }
    
    function test_Oracle_Events() public {
        // Test PriceSet event
        vm.expectEmit(true, false, false, true);
        emit PriceSet(
            address(collateralToken),
            2000e18,
            block.timestamp,
            block.number,
            owner
        );
        oracle.setPrice(address(collateralToken), 2000e18);
        
        // Test AuthorizedUpdaterSet event
        vm.expectEmit(true, false, false, true);
        emit AuthorizedUpdaterSet(authorizedUpdater, true);
        oracle.setAuthorizedUpdater(authorizedUpdater, true);
    }
    
    // ============ Integration Tests ============
    
    function test_TokenAndOracle_Integration() public {
        // Mint some tokens
        vm.prank(minter);
        collateralToken.mint(user1, 10 ether);
        
        // Set price
        oracle.setPrice(address(collateralToken), 2000e18);
        
        // Verify position value calculation
        uint256 balance = collateralToken.balanceOf(user1);
        uint256 price = oracle.getLatestPrice(address(collateralToken));
        uint256 positionValue = (balance * price) / 1e18;
        
        assertEq(balance, 10 ether);
        assertEq(price, 2000e18);
        assertEq(positionValue, 20000e18); // $20,000 worth of WETH
    }
    
    function test_DifferentDecimals_Tokens() public {
        // WETH (18 decimals)
        vm.prank(minter);
        collateralToken.mint(user1, 1 ether);
        assertEq(collateralToken.balanceOf(user1), 1e18);
        
        // USDC (6 decimals)
        vm.prank(minter);
        debtToken.mint(user1, 1000 * 1e6);
        assertEq(debtToken.balanceOf(user1), 1000e6);
        
        // Both should work with oracle (18 decimal prices)
        oracle.setPrice(address(collateralToken), 2000e18);
        oracle.setPrice(address(debtToken), 1e18);
    }
}
