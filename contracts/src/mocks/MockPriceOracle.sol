// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {IDemoOracle} from "../interfaces/IDemoOracle.sol";

/**
 * @title MockPriceOracle
 * @notice Centralized oracle for Reprieve demo lending protocols
 * @dev Owner-updated price feed with staleness tracking
 * @dev Prices are stored in WAD precision (18 decimals)
 */
contract MockPriceOracle is IDemoOracle, Ownable {
    
    struct PriceData {
        uint256 price;      // Price in WAD (18 decimals)
        uint256 timestamp;  // Last update timestamp
        uint256 blockNumber; // Block number of last update
    }
    
    /// @notice Price data per asset
    mapping(address => PriceData) public priceData;
    
    /// @notice Staleness threshold in seconds (default: 30 minutes)
    uint256 public stalenessThreshold;
    
    /// @notice Price feed is active (can be paused)
    bool public isActive;
    
    /// @notice Authorized updaters (in addition to owner)
    mapping(address => bool) public authorizedUpdaters;
    
    /// @notice Minimum price to prevent zero/negative prices
    uint256 public constant MIN_PRICE = 1e8; // $0.00000001 in WAD
    
    /// @notice Maximum price to prevent overflow
    uint256 public constant MAX_PRICE = 1e30; // $1,000,000,000,000 in WAD
    
    event PriceSet(
        address indexed asset,
        uint256 price,
        uint256 timestamp,
        uint256 blockNumber,
        address indexed updater
    );
    event AuthorizedUpdaterSet(address indexed updater, bool authorized);
    event OracleStatusSet(bool isActive);
    
    modifier onlyAuthorized() {
        require(
            msg.sender == owner() || authorizedUpdaters[msg.sender],
            "MockPriceOracle: caller is not authorized"
        );
        _;
    }
    
    modifier whenActive() {
        require(isActive, "MockPriceOracle: oracle is paused");
        _;
    }
    
    /**
     * @notice Constructor
     * @param initialOwner The initial owner address
     * @param _stalenessThreshold The staleness threshold in seconds
     */
    constructor(
        address initialOwner,
        uint256 _stalenessThreshold
    ) Ownable(initialOwner) {
        require(_stalenessThreshold > 0, "MockPriceOracle: staleness threshold must be > 0");
        stalenessThreshold = _stalenessThreshold;
        isActive = true;
        emit StalenessThresholdUpdated(_stalenessThreshold);
    }
    
    /**
     * @notice Set the price for an asset (owner or authorized updater only)
     * @param asset The asset address
     * @param price The new price in WAD precision (18 decimals)
     */
    function setPrice(
        address asset,
        uint256 price
    ) external override onlyAuthorized whenActive {
        require(asset != address(0), "MockPriceOracle: asset cannot be zero address");
        require(price >= MIN_PRICE, "MockPriceOracle: price below minimum");
        require(price <= MAX_PRICE, "MockPriceOracle: price above maximum");
        
        uint256 timestamp = block.timestamp;
        uint256 blockNum = block.number;
        
        priceData[asset] = PriceData({
            price: price,
            timestamp: timestamp,
            blockNumber: blockNum
        });
        
        emit PriceSet(asset, price, timestamp, blockNum, msg.sender);
        emit PriceUpdated(asset, price, timestamp);
    }
    
    /**
     * @notice Batch set prices for multiple assets
     * @param assets Array of asset addresses
     * @param prices Array of prices in WAD precision
     */
    function batchSetPrices(
        address[] calldata assets,
        uint256[] calldata prices
    ) external onlyAuthorized whenActive {
        require(assets.length == prices.length, "MockPriceOracle: length mismatch");
        require(assets.length > 0, "MockPriceOracle: empty arrays");
        
        uint256 timestamp = block.timestamp;
        uint256 blockNum = block.number;
        
        for (uint256 i = 0; i < assets.length; i++) {
            require(assets[i] != address(0), "MockPriceOracle: asset cannot be zero address");
            require(prices[i] >= MIN_PRICE, "MockPriceOracle: price below minimum");
            require(prices[i] <= MAX_PRICE, "MockPriceOracle: price above maximum");
            
            priceData[assets[i]] = PriceData({
                price: prices[i],
                timestamp: timestamp,
                blockNumber: blockNum
            });
            
            emit PriceSet(assets[i], prices[i], timestamp, blockNum, msg.sender);
            emit PriceUpdated(assets[i], prices[i], timestamp);
        }
    }
    
    /**
     * @notice Get the current price and timestamp for an asset
     * @param asset The asset address to query
     * @return price The price in WAD precision
     * @return timestamp The last update timestamp
     */
    function getPrice(
        address asset
    ) external view override returns (uint256 price, uint256 timestamp) {
        PriceData memory data = priceData[asset];
        require(data.timestamp > 0, "MockPriceOracle: price not set for asset");
        return (data.price, data.timestamp);
    }
    
    /**
     * @notice Get the latest price (reverts if stale or not set)
     * @param asset The asset address to query
     * @return price The price in WAD precision
     */
    function getLatestPrice(
        address asset
    ) external view override returns (uint256 price) {
        PriceData memory data = priceData[asset];
        require(data.timestamp > 0, "MockPriceOracle: price not set for asset");
        require(!isStale(asset), "MockPriceOracle: price is stale");
        return data.price;
    }
    
    /**
     * @notice Check if price data is stale
     * @param asset The asset address to query
     * @return isStale True if price is stale (older than stalenessThreshold)
     */
    function isStale(address asset) public view override returns (bool) {
        PriceData memory data = priceData[asset];
        if (data.timestamp == 0) {
            return true; // Never updated = stale
        }
        return block.timestamp > data.timestamp + stalenessThreshold;
    }
    
    /**
     * @notice Get the time elapsed since last update
     * @param asset The asset address to query
     * @return elapsed Time in seconds since last update (0 if never updated)
     */
    function timeSinceUpdate(address asset) external view returns (uint256 elapsed) {
        PriceData memory data = priceData[asset];
        if (data.timestamp == 0) {
            return type(uint256).max; // Never updated
        }
        return block.timestamp - data.timestamp;
    }
    
    /**
     * @notice Set the staleness threshold (owner only)
     * @param threshold The new threshold in seconds
     */
    function setStalenessThreshold(uint256 threshold) external override onlyOwner {
        require(threshold > 0, "MockPriceOracle: threshold must be > 0");
        stalenessThreshold = threshold;
        emit StalenessThresholdUpdated(threshold);
    }
    
    /**
     * @notice Authorize or deauthorize an updater (owner only)
     * @param updater The updater address
     * @param authorized Whether they are authorized
     */
    function setAuthorizedUpdater(address updater, bool authorized) external onlyOwner {
        require(updater != address(0), "MockPriceOracle: updater cannot be zero address");
        authorizedUpdaters[updater] = authorized;
        emit AuthorizedUpdaterSet(updater, authorized);
    }
    
    /**
     * @notice Set oracle active/paused (owner only)
     * @param _isActive Whether the oracle should be active
     */
    function setActive(bool _isActive) external onlyOwner {
        isActive = _isActive;
        emit OracleStatusSet(_isActive);
    }
    
    /**
     * @notice Check if a price has ever been set for an asset
     * @param asset The asset address to query
     * @return hasPrice True if price has been set
     */
    function hasPrice(address asset) external view returns (bool) {
        return priceData[asset].timestamp > 0;
    }
    
    /**
     * @notice Get the block number of the last price update
     * @param asset The asset address to query
     * @return blockNumber The block number of last update (0 if never updated)
     */
    function getLastUpdateBlock(address asset) external view returns (uint256 blockNumber) {
        return priceData[asset].blockNumber;
    }
}
