// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {IAdapterRegistry} from "./interfaces/IAdapterRegistry.sol";
import {ReprieveErrors} from "./libs/ReprieveErrors.sol";

/**
 * @title AdapterRegistry
 * @notice Registry for protocol-style adapter addresses used by executor
 * @dev Enables upgrade/replacement of adapter endpoints without redeploying executor
 */
contract AdapterRegistry is IAdapterRegistry, Ownable {
    
    /// @notice Protocol ID => Adapter address
    mapping(bytes32 => address) public adapters;
    
    /// @notice Protocol ID => Supported flag
    mapping(bytes32 => bool) public supportedProtocols;
    
    /// @notice Protocol IDs for iteration
    bytes32[] public registeredProtocolIds;
    
    /// @notice Protocol ID constants for demo
    bytes32 public constant AAVE_LIKE = keccak256("AAVE_LIKE");
    bytes32 public constant COMPOUND_LIKE = keccak256("COMPOUND_LIKE");
    bytes32 public constant MORPHO_LIKE = keccak256("MORPHO_LIKE");
    
    constructor(address initialOwner) Ownable(initialOwner) {}
    
    /**
     * @notice Set adapter address for a protocol
     * @param protocolId Protocol identifier (e.g., AAVE_LIKE)
     * @param adapter Adapter contract address
     */
    function setAdapter(bytes32 protocolId, address adapter) public override onlyOwner {
        if (adapter == address(0)) revert ReprieveErrors.ZeroAddress();
        if (!supportedProtocols[protocolId]) revert ReprieveErrors.UnsupportedProtocol(protocolId);
        
        // Add to list if first time setting
        if (adapters[protocolId] == address(0)) {
            registeredProtocolIds.push(protocolId);
        }
        
        adapters[protocolId] = adapter;
        emit AdapterSet(protocolId, adapter);
    }
    
    /**
     * @notice Set multiple adapters in a batch
     * @param ids Array of protocol identifiers
     * @param adapterAddresses Array of adapter addresses
     */
    function setMany(bytes32[] calldata ids, address[] calldata adapterAddresses) external onlyOwner {
        if (ids.length != adapterAddresses.length) revert ReprieveErrors.ArrayLengthMismatch();
        
        for (uint256 i = 0; i < ids.length; i++) {
            setAdapter(ids[i], adapterAddresses[i]);
        }
    }
    
    /**
     * @notice Get adapter address for a protocol
     * @param protocolId Protocol identifier
     * @return Adapter contract address
     */
    function getAdapter(bytes32 protocolId) external view override returns (address) {
        address adapter = adapters[protocolId];
        if (adapter == address(0)) revert ReprieveErrors.InvalidAdapter(protocolId);
        return adapter;
    }
    
    /**
     * @notice Check if adapter exists for a protocol
     * @param protocolId Protocol identifier
     * @return True if adapter is set
     */
    function hasAdapter(bytes32 protocolId) external view returns (bool) {
        return adapters[protocolId] != address(0);
    }
    
    /**
     * @notice Mark a protocol as supported/unsupported
     * @param protocolId Protocol identifier
     * @param supported True to support, false to remove support
     */
    function setSupportedProtocol(bytes32 protocolId, bool supported) external override onlyOwner {
        supportedProtocols[protocolId] = supported;
        emit ProtocolSupported(protocolId, supported);
    }
    
    /**
     * @notice Check if protocol is supported
     * @param protocolId Protocol identifier
     * @return True if supported
     */
    function isSupportedProtocol(bytes32 protocolId) external view override returns (bool) {
        return supportedProtocols[protocolId];
    }
    
    /**
     * @notice Get all registered protocol IDs
     * @return Array of protocol IDs
     */
    function getAllProtocolIds() external view returns (bytes32[] memory) {
        return registeredProtocolIds;
    }
    
    /**
     * @notice Get count of registered protocols
     * @return Number of protocols
     */
    function protocolCount() external view returns (uint256) {
        return registeredProtocolIds.length;
    }
    
    /**
     * @notice Initialize with demo protocol IDs
     * @dev Called once after deployment to set up AAVE_LIKE, COMPOUND_LIKE, MORPHO_LIKE
     */
    function initializeDemoProtocols() external onlyOwner {
        supportedProtocols[AAVE_LIKE] = true;
        supportedProtocols[COMPOUND_LIKE] = true;
        supportedProtocols[MORPHO_LIKE] = true;
        
        emit ProtocolSupported(AAVE_LIKE, true);
        emit ProtocolSupported(COMPOUND_LIKE, true);
        emit ProtocolSupported(MORPHO_LIKE, true);
    }
}
