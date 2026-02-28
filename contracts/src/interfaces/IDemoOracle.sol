// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IDemoOracle
 * @notice Centralized oracle interface for demo lending protocols
 * @dev Owner-updated price feed with staleness tracking
 */
interface IDemoOracle {
    /**
     * @notice Get the current price of an asset
     * @param asset The asset address to query
     * @return price The price in USD (WAD precision, 18 decimals)
     * @return timestamp The last update timestamp
     */
    function getPrice(address asset) external view returns (uint256 price, uint256 timestamp);
    
    /**
     * @notice Get the latest price (reverts if stale)
     * @param asset The asset address to query
     * @return price The price in USD (WAD precision)
     */
    function getLatestPrice(address asset) external view returns (uint256 price);
    
    /**
     * @notice Set the price for an asset (owner only)
     * @param asset The asset address
     * @param price The new price in USD (WAD precision)
     */
    function setPrice(address asset, uint256 price) external;
    
    /**
     * @notice Set the staleness threshold
     * @param threshold The new threshold in seconds
     */
    function setStalenessThreshold(uint256 threshold) external;
    
    /**
     * @notice Check if price data is stale
     * @param asset The asset address to query
     * @return isStale True if price is stale
     */
    function isStale(address asset) external view returns (bool isStale);
    
    /**
     * @notice Get the staleness threshold
     */
    function stalenessThreshold() external view returns (uint256);
    
    // ============ Events ============
    
    event PriceUpdated(address indexed asset, uint256 price, uint256 timestamp);
    event StalenessThresholdUpdated(uint256 threshold);
}
