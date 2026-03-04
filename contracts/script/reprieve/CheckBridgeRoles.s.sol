// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/**
 * @title CheckBridgeRoles
 * @notice Read-only script to inspect bridge minter/burner roles for a token/account pair.
 *
 * Required env:
 * - TOKEN_ADDRESS
 * - BRIDGE_ACCOUNT
 */
contract CheckBridgeRoles is Script {
    function run() external view {
        address tokenAddr = vm.envAddress("TOKEN_ADDRESS");
        address bridgeAccount = vm.envAddress("BRIDGE_ACCOUNT");

        MockERC20 token = MockERC20(tokenAddr);

        console.log("Checking bridge roles...");
        console.log("Chain ID:", block.chainid);
        console.log("Token:", tokenAddr);
        console.log("Bridge account:", bridgeAccount);
        console.log("Admin:", token.admin());
        console.log("Minter:", token.minter());
        console.log("bridgeMinters(account):", token.bridgeMinters(bridgeAccount));
        console.log("bridgeBurners(account):", token.bridgeBurners(bridgeAccount));
    }
}

