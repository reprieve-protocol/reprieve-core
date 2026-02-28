// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {RescueLog} from "../../src/reprieve/RescueLog.sol";

/**
 * @title DeployRescueLog
 * @notice Deploys the RescueLog contract
 * @dev Run with: forge script script/reprieve/DeployRescueLog.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract DeployRescueLog is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying RescueLog from:", deployer);
        console.log("Chain ID:", block.chainid);
        
        vm.startBroadcast(deployerPrivateKey);
        
        RescueLog log = new RescueLog(deployer);
        
        vm.stopBroadcast();
        
        console.log("\n=== RescueLog Deployment ===");
        console.log("RescueLog address:", address(log));
        console.log("Owner:", deployer);
    }
}
