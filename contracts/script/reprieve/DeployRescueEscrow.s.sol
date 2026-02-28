// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {RescueEscrow} from "../../src/reprieve/RescueEscrow.sol";
import {RescueLog} from "../../src/reprieve/RescueLog.sol";

/**
 * @title DeployRescueEscrow
 * @notice Deploys the RescueEscrow contract
 * @dev Run with: forge script script/reprieve/DeployRescueEscrow.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract DeployRescueEscrow is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address rescueLogAddr = vm.envAddress("RESCUE_LOG");
        
        console.log("Deploying RescueEscrow from:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("RescueLog:", rescueLogAddr);
        
        vm.startBroadcast(deployerPrivateKey);
        
        RescueEscrow escrow = new RescueEscrow(deployer, rescueLogAddr);
        
        vm.stopBroadcast();
        
        console.log("\n=== RescueEscrow Deployment ===");
        console.log("RescueEscrow address:", address(escrow));
        console.log("Owner:", deployer);
        console.log("Max retry count:", escrow.MAX_RETRY_COUNT());
        console.log("Escrow timeout:", escrow.ESCROW_TIMEOUT());
    }
}
