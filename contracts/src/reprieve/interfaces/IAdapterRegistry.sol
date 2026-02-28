// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAdapterRegistry
 * @notice Registry for protocol-style adapter addresses
 */
interface IAdapterRegistry {
    event AdapterSet(bytes32 indexed protocolId, address adapter);
    event ProtocolSupported(bytes32 indexed protocolId, bool supported);
    
    function setAdapter(bytes32 protocolId, address adapter) external;
    function getAdapter(bytes32 protocolId) external view returns (address);
    function setSupportedProtocol(bytes32 protocolId, bool supported) external;
    function isSupportedProtocol(bytes32 protocolId) external view returns (bool);
}
