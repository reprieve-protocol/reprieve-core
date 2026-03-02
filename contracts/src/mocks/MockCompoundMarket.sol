// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {BaseLendingEngine} from "./BaseLendingEngine.sol";
import {MockCToken} from "./MockCToken.sol";

/**
 * @notice Minimal Compound V2-style market mock for Reprieve demo
 * @dev Simplified: cToken receipt, mint/redeem/borrow/repay/liquidateBorrow
 */
contract MockCompoundMarket {
    using SafeERC20 for IERC20;

    address public immutable collateral;
    address public immutable debt;
    address public immutable oracle;
    BaseLendingEngine public immutable engine;
    MockCToken public immutable cToken;
    address public owner;

    // Cached risk params for easy access
    uint256 public immutable LTV_BPS;
    uint256 public immutable LIQUIDATION_THRESHOLD_BPS;

    event Mint(address indexed minter, uint256 mintAmount, uint256 mintTokens);
    event Redeem(address indexed redeemer, uint256 redeemAmount, uint256 redeemTokens);
    event Borrow(address indexed borrower, uint256 borrowAmount, uint256 accountBorrows, uint256 totalBorrows);
    event RepayBorrow(address indexed payer, address indexed borrower, uint256 repayAmount, uint256 accountBorrows, uint256 totalBorrows);
    event LiquidateBorrow(address indexed liquidator, address indexed borrower, uint256 repayAmount, address indexed cTokenCollateral, uint256 seizeTokens);

    constructor(address _collateral, address _debt, address _oracle, address _owner) {
        collateral = _collateral;
        debt = _debt;
        oracle = _oracle;
        engine = new BaseLendingEngine(_collateral, _debt, _oracle, _owner);
        
        // cToken with THIS contract as market (not engine)
        cToken = new MockCToken("cWETH", "cWETH", 18, _collateral, address(this));
        
        owner = _owner;
        
        // Cache risk params
        (LTV_BPS, LIQUIDATION_THRESHOLD_BPS,,) = engine.riskParams();
        
        // Max approve engine so it can pull from this pool
        IERC20(_collateral).approve(address(engine), type(uint256).max);
        IERC20(_debt).approve(address(engine), type(uint256).max);
    }

    function mint(address asset, uint256 amount) external {
        require(asset == collateral, "Invalid collateral");
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        engine.supply(asset, amount, msg.sender);
        cToken.mint(amount);
        emit Mint(msg.sender, amount, amount);
    }

    /**
     * @notice Mint collateral position on behalf of a target user.
     * @dev Rescue top-up path for adapter-driven supply.
     */
    function mintFor(address onBehalfOf, address asset, uint256 amount) external {
        require(onBehalfOf != address(0), "Invalid beneficiary");
        require(asset == collateral, "Invalid collateral");
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        engine.supply(asset, amount, onBehalfOf);
        cToken.mint(amount);
        emit Mint(onBehalfOf, amount, amount);
    }

    function redeem(address asset, uint256 cTokens) external {
        require(asset == collateral, "Invalid collateral");
        cToken.redeem(cTokens);
        engine.withdraw(asset, cTokens, msg.sender);
        IERC20(asset).safeTransfer(msg.sender, cTokens);
        emit Redeem(msg.sender, cTokens, cTokens);
    }

    function borrow(address asset, uint256 amount) external {
        require(asset == debt, "Invalid debt asset");
        engine.borrow(asset, amount, msg.sender);
        IERC20(asset).safeTransfer(msg.sender, amount);
        emit Borrow(msg.sender, amount, engine.getUserPosition(msg.sender).debt, 0);
    }

    function repayBorrow(address asset, uint256 amount) external {
        require(asset == debt, "Invalid debt asset");
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        engine.repay(asset, amount, msg.sender);
        emit RepayBorrow(msg.sender, msg.sender, amount, engine.getUserPosition(msg.sender).debt, 0);
    }

    function repayBorrowBehalf(address borrower, address asset, uint256 amount) external {
        require(asset == debt, "Invalid debt asset");
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        engine.repay(asset, amount, borrower);
        emit RepayBorrow(msg.sender, borrower, amount, engine.getUserPosition(borrower).debt, 0);
    }

    function liquidateBorrow(address borrower, uint256 repayAmount, address) external {
        IERC20(debt).safeTransferFrom(msg.sender, address(this), repayAmount);
        engine.liquidate(borrower);
        
        // Return seized collateral to liquidator
        uint256 seized = IERC20(collateral).balanceOf(address(this));
        IERC20(collateral).safeTransfer(msg.sender, seized);
        
        emit LiquidateBorrow(msg.sender, borrower, repayAmount, address(cToken), seized);
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
