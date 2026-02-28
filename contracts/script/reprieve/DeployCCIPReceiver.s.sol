// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {CCIPReceiver} from "../../src/reprieve/CCIPReceiver.sol";

/**
 * @title DeployCCIPReceiver
 * @notice Deploys the CCIPReceiver contract
 * @dev Run with: forge script script/reprieve/DeployCCIPReceiver.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract DeployCCIPReceiver is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        address executorAddr = vm.envAddress("RESCUE_EXECUTOR");
        address rescueEscrowAddr = vm.envAddress("RESCUE_ESCROW");
        address rescueLogAddr = vm.envAddress("RESCUE_LOG");
        
        console.log("Deploying CCIPReceiver from:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("Executor:", executorAddr);
        console.log("RescueEscrow:", rescueEscrowAddr);
        console.log("RescueLog:", rescueLogAddr);
        
        vm.startBroadcast(deployerPrivateKey);
        
        CCIPReceiver receiver = new CCIPReceiver(
            deployer,
            executorAddr,
            rescueEscrowAddr,
            rescueLogAddr
        );
        
        vm.stopBroadcast();
        
        console.log("\n=== CCIPReceiver Deployment ===");
        console.log("CCIPReceiver address:", address(receiver));
        console.log("Owner:", deployer);
    }
}
