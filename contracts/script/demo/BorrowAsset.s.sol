// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockAavePool} from "../../src/mocks/MockAavePool.sol";
import {MockCompoundMarket} from "../../src/mocks/MockCompoundMarket.sol";
import {MockMorphoMarket} from "../../src/mocks/MockMorphoMarket.sol";

/**
 * @title BorrowAsset
 * @notice User action: borrow debt asset from selected protocol market.
 */
contract BorrowAsset is Script {
    function run() external {
        uint256 fallbackPk = vm.envUint("PRIVATE_KEY");
        uint256 userPk = vm.envOr("USER_PRIVATE_KEY", fallbackPk);
        address user = vm.addr(userPk);

        address market = vm.envAddress("MARKET_ADDRESS");
        address asset = vm.envAddress("ASSET_ADDRESS");
        uint256 amount = vm.envUint("AMOUNT_RAW");
        string memory protocolRaw = vm.envString("PROTOCOL_KIND");
        string memory symbol = vm.envOr("ASSET_SYMBOL", string(""));
        string memory amountHuman = vm.envOr("AMOUNT_HUMAN", string(""));

        require(market != address(0), "BorrowAsset: MARKET_ADDRESS missing");
        require(asset != address(0), "BorrowAsset: ASSET_ADDRESS missing");
        require(amount > 0, "BorrowAsset: AMOUNT_RAW must be > 0");

        bytes32 protocol = _parseProtocol(protocolRaw);

        vm.startBroadcast(userPk);
        if (protocol == keccak256("AAVE")) {
            require(asset == MockAavePool(market).debt(), "BorrowAsset: non-debt asset for AAVE");
            MockAavePool(market).borrow(asset, amount, 2, 0, user);
        } else if (protocol == keccak256("COMPOUND")) {
            require(asset == MockCompoundMarket(market).debt(), "BorrowAsset: non-debt asset for Compound");
            MockCompoundMarket(market).borrow(asset, amount);
        } else if (protocol == keccak256("MORPHO")) {
            require(asset == MockMorphoMarket(market).loanToken(), "BorrowAsset: non-loan asset for Morpho");
            MockMorphoMarket(market).borrow(amount, user, "");
        } else {
            revert("BorrowAsset: unsupported protocol");
        }
        vm.stopBroadcast();

        console.log("Borrow executed.");
        console.log("Chain ID:", block.chainid);
        console.log("User:", user);
        console.log("Protocol:", protocolRaw);
        console.log("Market:", market);
        console.log("Asset:", asset);
        if (bytes(symbol).length > 0) console.log("Symbol:", symbol);
        if (bytes(amountHuman).length > 0) console.log("Amount (human):", amountHuman);
        console.log("Amount (raw):", amount);
    }

    function _parseProtocol(string memory raw) internal pure returns (bytes32) {
        bytes32 p = keccak256(bytes(raw));
        if (p == keccak256("AAVE")) return p;
        if (p == keccak256("COMPOUND")) return p;
        if (p == keccak256("MORPHO")) return p;
        revert("BorrowAsset: PROTOCOL_KIND must be AAVE/COMPOUND/MORPHO");
    }
}

