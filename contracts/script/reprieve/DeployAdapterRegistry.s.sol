// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AdapterRegistry} from "../../src/reprieve/AdapterRegistry.sol";

/**
 * @title DeployAdapterRegistry
 * @notice Deploys the AdapterRegistry contract
 * @dev Run with: forge script script/reprieve/DeployAdapterRegistry.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract DeployAdapterRegistry is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying AdapterRegistry from:", deployer);
        console.log("Chain ID:", block.chainid);
        
        vm.startBroadcast(deployerPrivateKey);
        
        AdapterRegistry registry = new AdapterRegistry(deployer);
        
        // Initialize demo protocols
        registry.initializeDemoProtocols();
        
        vm.stopBroadcast();
        
        console.log("\n=== AdapterRegistry Deployment ===");
        console.log("Registry address:", address(registry));
        console.log("AAVE_LIKE ID:", uint256(registry.AAVE_LIKE()));
        console.log("COMPOUND_LIKE ID:", uint256(registry.COMPOUND_LIKE()));
        console.log("MORPHO_LIKE ID:", uint256(registry.MORPHO_LIKE()));
        
        // Verify protocols are supported
        console.log("\n=== Protocol Support Status ===");
        console.log("AAVE_LIKE supported:", registry.isSupportedProtocol(registry.AAVE_LIKE()));
        console.log("COMPOUND_LIKE supported:", registry.isSupportedProtocol(registry.COMPOUND_LIKE()));
        console.log("MORPHO_LIKE supported:", registry.isSupportedProtocol(registry.MORPHO_LIKE()));
    }
}
