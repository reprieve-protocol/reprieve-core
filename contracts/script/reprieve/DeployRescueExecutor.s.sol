// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {RescueExecutor} from "../../src/reprieve/RescueExecutor.sol";

/**
 * @title DeployRescueExecutor
 * @notice Deploys the RescueExecutor contract
 * @dev Run with: forge script script/reprieve/DeployRescueExecutor.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract DeployRescueExecutor is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        address rescueLogAddr = vm.envAddress("RESCUE_LOG");
        address rescueEscrowAddr = vm.envAddress("RESCUE_ESCROW");
        address adapterRegistryAddr = vm.envAddress("ADAPTER_REGISTRY");
        
        console.log("Deploying RescueExecutor from:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("RescueLog:", rescueLogAddr);
        console.log("RescueEscrow:", rescueEscrowAddr);
        console.log("AdapterRegistry:", adapterRegistryAddr);
        
        vm.startBroadcast(deployerPrivateKey);
        
        RescueExecutor executor = new RescueExecutor(
            deployer,
            rescueLogAddr,
            rescueEscrowAddr,
            adapterRegistryAddr
        );
        
        vm.stopBroadcast();
        
        console.log("\n=== RescueExecutor Deployment ===");
        console.log("RescueExecutor address:", address(executor));
        console.log("Owner:", deployer);
        console.log("Source reserve factor:", executor.SOURCE_RESERVE_FACTOR_BPS(), "bps");
    }
}
