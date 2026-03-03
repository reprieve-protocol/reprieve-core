// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockPriceOracle} from "../../src/mocks/MockPriceOracle.sol";

/**
 * @title SetOraclePrice
 * @notice Sets a single asset price in MockPriceOracle.
 * @dev Intended to be called by scripts/ops.sh set-oracle-price.
 */
contract SetOraclePrice is Script {
    function run() external {
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(ownerPrivateKey);

        address oracle = vm.envAddress("PRICE_ORACLE");
        address asset = vm.envAddress("ASSET_ADDRESS");
        uint256 priceWad = vm.envUint("PRICE_WAD");
        string memory symbol = vm.envOr("ASSET_SYMBOL", string(""));
        string memory priceHuman = vm.envOr("PRICE_HUMAN", string(""));

        require(oracle != address(0), "SetOraclePrice: missing PRICE_ORACLE");
        require(asset != address(0), "SetOraclePrice: missing ASSET_ADDRESS");
        require(priceWad > 0, "SetOraclePrice: PRICE_WAD must be > 0");

        console.log("Setting oracle price...");
        console.log("Chain ID:", block.chainid);
        console.log("Owner:", owner);
        console.log("Oracle:", oracle);
        console.log("Asset:", asset);
        if (bytes(symbol).length > 0) {
            console.log("Symbol:", symbol);
        }
        if (bytes(priceHuman).length > 0) {
            console.log("Price (human):", priceHuman);
        }
        console.log("Price (wad):", priceWad);

        vm.startBroadcast(ownerPrivateKey);
        MockPriceOracle(oracle).setPrice(asset, priceWad);
        vm.stopBroadcast();

        (uint256 storedPrice, uint256 updatedAt) = MockPriceOracle(oracle).getPrice(asset);
        require(storedPrice == priceWad, "SetOraclePrice: oracle value mismatch");

        console.log("Oracle price updated.");
        console.log("Stored price (wad):", storedPrice);
        console.log("Updated timestamp:", updatedAt);
    }
}

