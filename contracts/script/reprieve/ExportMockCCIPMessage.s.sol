// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockCCIPRouter} from "../../src/mocks/MockCCIPRouter.sol";

/**
 * @title ExportMockCCIPMessage
 * @notice Reads a source-router stored message and exports relay env vars for destination delivery.
 * @dev Output file can be sourced by scripts/ops.sh before running RelayExternalMockMessage.
 */
contract ExportMockCCIPMessage is Script {
    function run() external {
        address routerAddr = vm.envAddress("MOCK_CCIP_ROUTER");
        bytes32 messageId = vm.envBytes32("MOCK_MESSAGE_ID");
        string memory exportPath = vm.envOr("MOCK_EXPORT_PATH", string("./config/mock-relay-message.env"));

        MockCCIPRouter router = MockCCIPRouter(routerAddr);
        MockCCIPRouter.StoredMessage memory stored = router.getMessage(messageId);

        require(stored.timestamp != 0, "ExportMockCCIPMessage: message not found");
        require(stored.tokenAmounts.length > 0, "ExportMockCCIPMessage: token amounts empty");

        address sourceToken = stored.tokenAmounts[0].token;
        uint256 sourceAmount = stored.tokenAmounts[0].amount;
        require(sourceToken != address(0) && sourceAmount > 0, "ExportMockCCIPMessage: invalid source token amount");

        address destinationToken = router.tokenMappings(stored.destinationChainSelector, sourceToken);
        destinationToken = vm.envOr("MOCK_EXPORT_DEST_TOKEN", destinationToken);
        require(destinationToken != address(0), "ExportMockCCIPMessage: destination token not configured");

        address receiver = _decodeReceiver(stored.receiver);

        string memory output = string.concat(
            "MOCK_MESSAGE_ID=", vm.toString(messageId), "\n",
            "MOCK_SOURCE_SELECTOR=", vm.toString(uint256(stored.sourceChainSelector)), "\n",
            "MOCK_SOURCE_SENDER=", vm.toString(stored.sender), "\n",
            "MOCK_DEST_RECEIVER=", vm.toString(receiver), "\n",
            "MOCK_PAYLOAD=", vm.toString(stored.data), "\n",
            "MOCK_DEST_TOKEN=", vm.toString(destinationToken), "\n",
            "MOCK_DEST_AMOUNT=", vm.toString(sourceAmount), "\n",
            "MOCK_DEST_SELECTOR=", vm.toString(uint256(stored.destinationChainSelector)), "\n"
        );

        vm.writeFile(exportPath, output);
        console.log("Mock relay export written:", exportPath);
    }

    function _decodeReceiver(bytes memory receiver) internal pure returns (address) {
        if (receiver.length == 32) {
            return abi.decode(receiver, (address));
        }
        if (receiver.length == 20) {
            return address(uint160(bytes20(receiver)));
        }
        revert("ExportMockCCIPMessage: invalid receiver bytes");
    }
}

