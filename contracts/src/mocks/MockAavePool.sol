// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {BaseLendingEngine} from "./BaseLendingEngine.sol";
import {MockAToken} from "./MockAToken.sol";

/**
 * @notice Minimal Aave V3 Pool mock for Reprieve demo
 * @dev Simplified: aToken receipt, basic supply/borrow/liquidate
 */
contract MockAavePool {
    using SafeERC20 for IERC20;

    address public immutable collateral;
    address public immutable debt;
    address public immutable oracle;
    BaseLendingEngine public immutable engine;
    MockAToken public immutable aToken;
    address public owner;

    // Cached risk params for easy access
    uint256 public immutable LTV_BPS;
    uint256 public immutable LIQUIDATION_THRESHOLD_BPS;

    mapping(address => mapping(address => uint256)) public userCollateral;

    event Supply(address indexed asset, address indexed sender, address indexed onBehalfOf, uint256 amount);
    event Borrow(address indexed asset, address indexed user, uint256 amount);
    event Repay(address indexed asset, address indexed user, uint256 amount);
    event LiquidationCall(address indexed collateralAsset, address indexed debtAsset, address indexed user, uint256 debtToCover, bool receiveAToken);

    constructor(address _collateral, address _debt, address _oracle, address _owner) {
        collateral = _collateral;
        debt = _debt;
        oracle = _oracle;
        
        // Create engine first (aToken will need engine address)
        engine = new BaseLendingEngine(_collateral, _debt, _oracle, _owner);
        
        // Create aToken with THIS contract as pool (not engine)
        aToken = new MockAToken("aWETH", "aWETH", 18, _collateral, address(this));
        
        owner = _owner;
        
        // Cache risk params
        (LTV_BPS, LIQUIDATION_THRESHOLD_BPS,,) = engine.riskParams();
        
        // Max approve engine so it can pull from this pool
        IERC20(_collateral).approve(address(engine), type(uint256).max);
        IERC20(_debt).approve(address(engine), type(uint256).max);
    }

    function supply(address asset, uint256 amount, address onBehalfOf, uint16) external {
        require(asset == collateral, "Invalid collateral");
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        engine.supply(asset, amount, onBehalfOf);
        aToken.mint(msg.sender, onBehalfOf, amount, 0);
        emit Supply(asset, msg.sender, onBehalfOf, amount);
    }

    function borrow(address asset, uint256 amount, uint256, uint16, address onBehalfOf) external {
        require(asset == debt, "Invalid debt asset");
        engine.borrow(asset, amount, onBehalfOf);
        IERC20(asset).safeTransfer(msg.sender, amount);
        emit Borrow(asset, onBehalfOf, amount);
    }

    function repay(address asset, uint256 amount, uint256, address onBehalfOf) external returns (uint256) {
        require(asset == debt, "Invalid debt asset");
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        engine.repay(asset, amount, onBehalfOf);
        emit Repay(asset, onBehalfOf, amount);
        return amount;
    }

    function withdraw(address asset, uint256 amount, address to) external {
        require(asset == collateral, "Invalid collateral");
        
        // Burn aTokens from msg.sender (adapter has transferred them to itself)
        aToken.burn(msg.sender, msg.sender, amount, 0);
        
        // Transfer collateral from engine to recipient
        engine.withdraw(asset, amount, to);
    }
    
    /**
     * @notice Withdraw on behalf of a user (for rescue scenarios)
     * @param user User whose position to withdraw from
     * @param asset Collateral asset
     * @param amount Amount to withdraw
     * @param to Recipient address
     */
    function withdrawFor(address user, address asset, uint256 amount, address to) external {
        require(asset == collateral, "Invalid collateral");
        
        // Burn aTokens from caller (adapter must have transferred them from user first)
        aToken.burn(msg.sender, msg.sender, amount, 0);
        
        // Withdraw from engine on behalf of user
        engine.withdrawOnBehalfOf(user, asset, amount, to);
    }

    function liquidationCall(address, address debtAsset, address user, uint256 debtToCover, bool) external {
        require(debtAsset == debt, "Invalid debt asset");
        
        IERC20(debtAsset).safeTransferFrom(msg.sender, address(this), debtToCover);
        engine.liquidate(user);
        
        // Return seized collateral to liquidator
        uint256 seized = IERC20(collateral).balanceOf(address(this));
        IERC20(collateral).safeTransfer(msg.sender, seized);
        
        emit LiquidationCall(collateral, debtAsset, user, debtToCover, false);
    }

    function getUserPosition(address user) external view returns (BaseLendingEngine.Position memory) {
        return engine.getUserPosition(user);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return engine.getCurrentHealthFactor(user);
    }

    function liquidationThresholdBps() external view returns (uint256) {
        return LIQUIDATION_THRESHOLD_BPS;
    }

    function ltvBps() external view returns (uint256) {
        return LTV_BPS;
    }

    function collateralDecimals() external pure returns (uint8) { return 18; }
    function debtDecimals() external pure returns (uint8) { return 6; }
}
