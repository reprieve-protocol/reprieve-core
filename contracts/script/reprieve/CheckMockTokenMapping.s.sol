// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockCCIPRouter} from "../../src/mocks/MockCCIPRouter.sol";
import {IERC20Metadata} from "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title CheckMockTokenMapping
 * @notice Read-only script to inspect source->destination token mapping on a MockCCIPRouter lane.
 *
 * Required env:
 * - SOURCE_ROUTER
 * - DEST_CHAIN_SELECTOR
 * - SOURCE_TOKEN
 *
 * Optional env:
 * - SOURCE_TOKEN_SYMBOL
 */
contract CheckMockTokenMapping is Script {
    function run() external view {
        address sourceRouterAddr = vm.envAddress("SOURCE_ROUTER");
        uint64 destinationSelector = uint64(vm.envUint("DEST_CHAIN_SELECTOR"));
        address sourceToken = vm.envAddress("SOURCE_TOKEN");
        string memory sourceTokenSymbolHint = vm.envOr("SOURCE_TOKEN_SYMBOL", string(""));

        MockCCIPRouter router = MockCCIPRouter(sourceRouterAddr);
        uint64 sourceSelector = router.currentChainSelector();
        bool laneEnabled = router.lanes(sourceSelector, destinationSelector);
        address receiver = router.chainReceivers(destinationSelector);
        address destinationToken = router.tokenMappings(destinationSelector, sourceToken);

        console.log("Checking mock CCIP mapping...");
        console.log("Chain ID:", block.chainid);
        console.log("Source router:", sourceRouterAddr);
        console.log("Source selector:", sourceSelector);
        console.log("Destination selector:", destinationSelector);
        console.log("Lane enabled:", laneEnabled);
        console.log("Destination receiver:", receiver);
        if (bytes(sourceTokenSymbolHint).length > 0) {
            console.log("Source token symbol hint:", sourceTokenSymbolHint);
        }
        console.log("Source token:", sourceToken);
        console.log("Mapped destination token:", destinationToken);

        _logTokenMeta("Source", sourceToken);
        if (destinationToken != address(0)) {
            _logTokenMeta("Destination", destinationToken);
        }
    }

    function _logTokenMeta(string memory label, address token) internal view {
        string memory symbol = _trySymbol(token);
        uint8 decimals = _tryDecimals(token);
        console.log(string.concat(label, " token symbol:"), symbol);
        console.log(string.concat(label, " token decimals:"), uint256(decimals));
    }

    function _trySymbol(address token) internal view returns (string memory) {
        try IERC20Metadata(token).symbol() returns (string memory s) {
            return s;
        } catch {
            return "<unknown>";
        }
    }

    function _tryDecimals(address token) internal view returns (uint8) {
        try IERC20Metadata(token).decimals() returns (uint8 d) {
            return d;
        } catch {
            return 18;
        }
    }
}

