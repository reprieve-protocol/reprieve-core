// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AdapterRegistry} from "../../src/reprieve/AdapterRegistry.sol";

/**
 * @title WireAdapterRegistry
 * @notice Wires deployed adapters to the registry
 * @dev Run after DeployAdapterRegistry and DeployAdapters
 * @dev Required env vars: REGISTRY, AAVE_ADAPTER, COMPOUND_ADAPTER, MORPHO_ADAPTER
 */
contract WireAdapterRegistry is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        address registryAddr = vm.envAddress("REGISTRY");
        address aaveAdapter = vm.envAddress("AAVE_ADAPTER");
        address compoundAdapter = vm.envAddress("COMPOUND_ADAPTER");
        address morphoAdapter = vm.envAddress("MORPHO_ADAPTER");
        
        console.log("Wiring AdapterRegistry from:", deployer);
        console.log("Registry:", registryAddr);
        console.log("AAVE_ADAPTER:", aaveAdapter);
        console.log("COMPOUND_ADAPTER:", compoundAdapter);
        console.log("MORPHO_ADAPTER:", morphoAdapter);
        
        AdapterRegistry registry = AdapterRegistry(registryAddr);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Set adapters for each protocol
        registry.setAdapter(registry.AAVE_LIKE(), aaveAdapter);
        registry.setAdapter(registry.COMPOUND_LIKE(), compoundAdapter);
        registry.setAdapter(registry.MORPHO_LIKE(), morphoAdapter);
        
        vm.stopBroadcast();
        
        console.log("\n=== Wiring Complete ===");
        console.log("AAVE_LIKE ->", registry.getAdapter(registry.AAVE_LIKE()));
        console.log("COMPOUND_LIKE ->", registry.getAdapter(registry.COMPOUND_LIKE()));
        console.log("MORPHO_LIKE ->", registry.getAdapter(registry.MORPHO_LIKE()));
        console.log("Total protocols:", registry.protocolCount());
    }
}
