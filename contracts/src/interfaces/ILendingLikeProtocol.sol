// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILendingLikeProtocol
 * @notice Common interface for all protocol mimics (Aave-like, Compound-like, Morpho-like)
 * @dev Used by Reprieve adapters to interact with lending protocols uniformly
 */
interface ILendingLikeProtocol {
    struct Position {
        uint256 collateral;
        uint256 debt;
        uint256 ltvBps;                    // Loan-to-Value in basis points
        uint256 liquidationThresholdBps;   // Liquidation threshold in basis points
    }

    // ============ Position Reads ============
    
    /**
     * @notice Get user's position data
     * @param user The address to query
     * @return Position struct with collateral, debt, LTV, and liquidation threshold
     */
    function getUserPosition(address user) external view returns (Position memory);
    
    /**
     * @notice Calculate health factor for a user
     * @param user The address to query
     * @param price Current collateral price (WAD precision)
     * @return hfWad Health factor in WAD precision (1e18 = 1.0)
     */
    function getHealthFactor(address user, uint256 price) external view returns (uint256 hfWad);
    
    /**
     * @notice Get the current collateral token
     */
    function collateralAsset() external view returns (address);
    
    /**
     * @notice Get the current debt token
     */
    function debtAsset() external view returns (address);
    
    /**
     * @notice Get the collateral token decimals
     */
    function collateralDecimals() external view returns (uint8);
    
    /**
     * @notice Get the debt token decimals
     */
    function debtDecimals() external view returns (uint8);
    
    // ============ User Actions ============
    
    /**
     * @notice Supply collateral to the protocol
     * @param asset The collateral token address
     * @param amount The amount to supply
     * @param onBehalfOf The address to supply for
     */
    function supply(address asset, uint256 amount, address onBehalfOf) external;
    
    /**
     * @notice Withdraw collateral from the protocol
     * @param asset The collateral token address
     * @param amount The amount to withdraw
     * @param to The address to send withdrawn collateral to
     */
    function withdraw(address asset, uint256 amount, address to) external;
    
    /**
     * @notice Borrow debt asset from the protocol
     * @param asset The debt token address
     * @param amount The amount to borrow
     * @param onBehalfOf The address to borrow for
     */
    function borrow(address asset, uint256 amount, address onBehalfOf) external;
    
    /**
     * @notice Repay debt to the protocol
     * @param asset The debt token address
     * @param amount The amount to repay
     * @param onBehalfOf The address whose debt is being repaid
     */
    function repay(address asset, uint256 amount, address onBehalfOf) external;
    
    // ============ Liquidation ============
    
    /**
     * @notice Liquidate an unhealthy position
     * @param user The address to liquidate
     * @dev Callable by anyone when HF < 1.0
     */
    function liquidate(address user) external;
    
    // ============ Events ============
    
    event Supplied(address indexed user, address indexed asset, uint256 amount);
    event Withdrawn(address indexed user, address indexed asset, uint256 amount, address indexed to);
    event Borrowed(address indexed user, address indexed asset, uint256 amount);
    event Repaid(address indexed user, address indexed asset, uint256 amount, address indexed onBehalfOf);
    event PositionUpdated(address indexed user, uint256 collateral, uint256 debt, uint256 hfWad);
    event Liquidated(address indexed user, address indexed liquidator, uint256 debtRepaid, uint256 collateralSeized);
}

/**
 * @title IERC20Metadata
 * @notice Interface for ERC20 metadata
 */
interface IERC20Metadata {
    function decimals() external view returns (uint8);
}
