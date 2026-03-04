// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/**
 * @title SetBridgeRoles
 * @notice Sets bridge minter/burner roles on MockERC20 for a target account.
 *
 * Required env:
 * - PRIVATE_KEY
 * - TOKEN_ADDRESS
 * - BRIDGE_ACCOUNT
 *
 * Optional env:
 * - ROLE_KIND (MINTER|BURNER|BOTH), default BOTH
 * - ROLE_ALLOWED (true|false), default true
 */
contract SetBridgeRoles is Script {
    function run() external {
        uint256 ownerPk = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(ownerPk);

        address tokenAddr = vm.envAddress("TOKEN_ADDRESS");
        address bridgeAccount = vm.envAddress("BRIDGE_ACCOUNT");
        string memory roleKind = vm.envOr("ROLE_KIND", string("BOTH"));
        bool allowed = vm.envOr("ROLE_ALLOWED", true);

        MockERC20 token = MockERC20(tokenAddr);

        bool setMinter = _eq(roleKind, "MINTER") || _eq(roleKind, "BOTH");
        bool setBurner = _eq(roleKind, "BURNER") || _eq(roleKind, "BOTH");
        require(setMinter || setBurner, "SetBridgeRoles: ROLE_KIND must be MINTER|BURNER|BOTH");

        console.log("Setting bridge roles...");
        console.log("Chain ID:", block.chainid);
        console.log("Owner:", owner);
        console.log("Token:", tokenAddr);
        console.log("Bridge account:", bridgeAccount);
        console.log("Role kind:", roleKind);
        console.log("Allowed:", allowed);

        vm.startBroadcast(ownerPk);
        if (setMinter) {
            token.setBridgeMinter(bridgeAccount, allowed);
        }
        if (setBurner) {
            token.setBridgeBurner(bridgeAccount, allowed);
        }
        vm.stopBroadcast();

        console.log("Updated bridgeMinters(account):", token.bridgeMinters(bridgeAccount));
        console.log("Updated bridgeBurners(account):", token.bridgeBurners(bridgeAccount));
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}

