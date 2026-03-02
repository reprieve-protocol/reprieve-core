// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockCCIPRouter} from "../../src/mocks/MockCCIPRouter.sol";

/**
 * @title RelayExternalMockMessage
 * @notice Delivers a source-router message on destination router for two-network mock relay demos.
 */
contract RelayExternalMockMessage is Script {
    function run() external {
        uint256 ownerPk = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(ownerPk);

        address routerAddr = vm.envOr("MOCK_CCIP_ROUTER", vm.envAddress("CCIP_ROUTER"));
        bytes32 messageId = vm.envBytes32("MOCK_MESSAGE_ID");
        uint64 sourceSelector = uint64(vm.envUint("MOCK_SOURCE_SELECTOR"));
        address sourceSender = vm.envAddress("MOCK_SOURCE_SENDER");
        address receiver = vm.envAddress("MOCK_DEST_RECEIVER");
        bytes memory payload = vm.parseBytes(vm.envString("MOCK_PAYLOAD"));
        address destinationToken = vm.envAddress("MOCK_DEST_TOKEN");
        uint256 destinationAmount = vm.envUint("MOCK_DEST_AMOUNT");

        console.log("Relaying external mock message on chain:", block.chainid);
        console.log("Owner:", owner);
        console.log("Router:", routerAddr);
        console.log("MessageId:", vm.toString(messageId));
        console.log("Receiver:", receiver);

        vm.startBroadcast(ownerPk);
        MockCCIPRouter(routerAddr).deliverExternalMessage(
            messageId,
            sourceSelector,
            sourceSender,
            receiver,
            payload,
            destinationToken,
            destinationAmount
        );
        vm.stopBroadcast();

        console.log("External mock relay delivered.");
    }
}

