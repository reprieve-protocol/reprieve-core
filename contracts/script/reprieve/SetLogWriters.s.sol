// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {RescueLog} from "../../src/reprieve/RescueLog.sol";

/**
 * @title SetLogWriters
 * @notice Authorizes executor, receiver, and escrow contracts to write logs
 * @dev Run after deploying RescueLog, RescueExecutor, CCIPReceiver, and RescueEscrow
 */
contract SetLogWriters is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        address rescueLogAddr = vm.envAddress("RESCUE_LOG");
        address executorAddr = vm.envAddress("RESCUE_EXECUTOR");
        address receiverAddr = vm.envAddress("CCIP_RECEIVER");
        address escrowAddr = vm.envAddress("RESCUE_ESCROW");
        
        console.log("Setting log writers from:", deployer);
        console.log("RescueLog:", rescueLogAddr);
        console.log("Executor:", executorAddr);
        console.log("Receiver:", receiverAddr);
        console.log("Escrow:", escrowAddr);
        
        RescueLog rescueLog = RescueLog(rescueLogAddr);
        
        vm.startBroadcast(deployerPrivateKey);
        
        rescueLog.setAuthorizedWriter(executorAddr, true);
        rescueLog.setAuthorizedWriter(receiverAddr, true);
        rescueLog.setAuthorizedWriter(escrowAddr, true);
        
        vm.stopBroadcast();
        
        console.log("\n=== Writers Authorized ===");
        console.log("Executor authorized:", rescueLog.isAuthorizedWriter(executorAddr));
        console.log("Receiver authorized:", rescueLog.isAuthorizedWriter(receiverAddr));
        console.log("Escrow authorized:", rescueLog.isAuthorizedWriter(escrowAddr));
    }
}
