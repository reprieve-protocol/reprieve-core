// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IReprieveAdapter
 * @notice Adapter interface for Reprieve to interact with various lending protocols
 * @dev Each protocol (Aave, Compound, Morpho) has its own adapter implementing this interface
 */
interface IReprieveAdapter {
    struct Position {
        address protocol;           // The lending protocol address
        address collateralAsset;    // Collateral token address
        address debtAsset;          // Debt token address
        uint256 collateralAmount;   // Collateral balance
        uint256 debtAmount;         // Debt balance
        uint256 healthFactor;       // Health factor in WAD precision
        uint256 ltvBps;             // Current LTV in basis points
        uint256 maxLtvBps;          // Maximum allowed LTV in basis points
        uint256 liquidationThresholdBps; // Liquidation threshold in basis points
    }
    
    /**
     * @notice Discover all positions for a user in this protocol
     * @param user The address to query
     * @return positions Array of Position structs
     */
    function discoverPositions(address user) external view returns (Position[] memory positions);
    
    /**
     * @notice Get health factor for a specific user
     * @param user The address to query
     * @return hfWad Health factor in WAD precision (1e18 = 1.0)
     */
    function healthFactor(address user) external view returns (uint256 hfWad);
    
    /**
     * @notice Get available (withdrawable) collateral for a user
     * @param user The address to query
     * @param asset The collateral asset address
     * @return amount The available collateral amount
     */
    function availableCollateral(address user, address asset) external view returns (uint256 amount);
    
    /**
     * @notice Get total debt for a user
     * @param user The address to query
     * @param asset The debt asset address
     * @return amount The debt amount
     */
    function getDebt(address user, address asset) external view returns (uint256 amount);
    
    /**
     * @notice Withdraw collateral for rescue purposes
     * @param user The user whose collateral to withdraw
     * @param asset The collateral asset address
     * @param amount The amount to withdraw
     * @param to The address to send withdrawn collateral to
     * @dev Requires proper approval from the user
     */
    function withdrawForRescue(address user, address asset, uint256 amount, address to) external;
    
    /**
     * @notice Repay debt for rescue purposes
     * @param user The user whose debt to repay (onBehalfOf)
     * @param asset The debt asset address
     * @param amount The amount to repay
     * @dev Pulls tokens from msg.sender
     */
    function repayForRescue(address user, address asset, uint256 amount) external;
    
    /**
     * @notice Check if this adapter supports a given asset pair
     * @param collateralAsset The collateral token address
     * @param debtAsset The debt token address
     * @return supported True if the pair is supported
     */
    function supportsPair(address collateralAsset, address debtAsset) external view returns (bool supported);
    
    /**
     * @notice Get the protocol name/identifier
     */
    function protocolName() external view returns (string memory name);
    
    /**
     * @notice Get the underlying protocol address
     */
    function protocolAddress() external view returns (address);
    
    // ============ Events ============
    
    event PositionDiscovered(address indexed user, address indexed collateralAsset, uint256 collateralAmount, uint256 debtAmount);
    event CollateralWithdrawn(address indexed user, address indexed asset, uint256 amount, address indexed to);
    event DebtRepaid(address indexed user, address indexed asset, uint256 amount);
}
