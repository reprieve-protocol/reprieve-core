// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockCCIPRouter} from "../../src/mocks/MockCCIPRouter.sol";

/**
 * @title SetMockCcipFee
 * @notice Updates mock CCIP fee for a destination selector on the router for the current chain.
 *
 * Required env:
 * - PRIVATE_KEY
 * - CCIP_ROUTER
 * - DEST_CHAIN_SELECTOR
 * - MOCK_FEE_WEI
 */
contract SetMockCcipFee is Script {
    function run() external {
        uint256 ownerPk = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(ownerPk);

        address routerAddr = vm.envAddress("CCIP_ROUTER");
        uint64 destSelector = uint64(vm.envUint("DEST_CHAIN_SELECTOR"));
        uint256 feeWei = vm.envUint("MOCK_FEE_WEI");

        MockCCIPRouter router = MockCCIPRouter(routerAddr);
        uint256 beforeFee = router.mockFees(destSelector);

        console.log("Setting mock CCIP fee...");
        console.log("Chain ID:", block.chainid);
        console.log("Owner:", owner);
        console.log("Router:", routerAddr);
        console.log("Destination selector:", uint256(destSelector));
        console.log("Previous fee (wei):", beforeFee);
        console.log("New fee (wei):", feeWei);

        vm.startBroadcast(ownerPk);
        router.setMockFee(destSelector, feeWei);
        vm.stopBroadcast();

        uint256 afterFee = router.mockFees(destSelector);
        console.log("Updated fee (wei):", afterFee);
    }
}
