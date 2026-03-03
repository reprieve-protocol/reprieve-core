// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockAavePool} from "../../src/mocks/MockAavePool.sol";
import {MockCompoundMarket} from "../../src/mocks/MockCompoundMarket.sol";
import {MockMorphoMarket} from "../../src/mocks/MockMorphoMarket.sol";
import {IReprieveAdapter} from "../../src/interfaces/IReprieveAdapter.sol";

/**
 * @title RepayAsset
 * @notice User action: repay debt asset in selected protocol market.
 */
contract RepayAsset is Script {
    function run() external {
        uint256 fallbackPk = vm.envUint("PRIVATE_KEY");
        uint256 userPk = vm.envOr("USER_PRIVATE_KEY", fallbackPk);
        uint256 minterPk = vm.envOr("MINTER_PRIVATE_KEY", fallbackPk);
        address user = vm.addr(userPk);

        address adapter = vm.envAddress("ADAPTER_ADDRESS");
        address market = vm.envAddress("MARKET_ADDRESS");
        address asset = vm.envAddress("ASSET_ADDRESS");
        uint256 amount = vm.envUint("AMOUNT_RAW");
        string memory protocolRaw = vm.envString("PROTOCOL_KIND");
        string memory symbol = vm.envOr("ASSET_SYMBOL", string(""));
        string memory amountHuman = vm.envOr("AMOUNT_HUMAN", string(""));

        require(adapter != address(0), "RepayAsset: ADAPTER_ADDRESS missing");
        require(market != address(0), "RepayAsset: MARKET_ADDRESS missing");
        require(asset != address(0), "RepayAsset: ASSET_ADDRESS missing");
        require(amount > 0, "RepayAsset: AMOUNT_RAW must be > 0");

        bytes32 protocol = _parseProtocol(protocolRaw);

        uint256 currentBalance = IERC20(asset).balanceOf(user);
        if (currentBalance < amount) {
            uint256 mintAmount = amount - currentBalance;
            vm.startBroadcast(minterPk);
            MockERC20(asset).mint(user, mintAmount);
            vm.stopBroadcast();
            console.log("User balance insufficient, minted top-up:", mintAmount);
        }

        vm.startBroadcast(userPk);
        IERC20(asset).approve(adapter, amount);

        if (protocol == keccak256("AAVE")) {
            require(asset == MockAavePool(market).debt(), "RepayAsset: non-debt asset for AAVE");
        } else if (protocol == keccak256("COMPOUND")) {
            require(asset == MockCompoundMarket(market).debt(), "RepayAsset: non-debt asset for Compound");
        } else if (protocol == keccak256("MORPHO")) {
            require(asset == MockMorphoMarket(market).loanToken(), "RepayAsset: non-loan asset for Morpho");
        } else {
            revert("RepayAsset: unsupported protocol");
        }

        IReprieveAdapter(adapter).repayForRescue(user, asset, amount);
        vm.stopBroadcast();

        console.log("Repay executed.");
        console.log("Chain ID:", block.chainid);
        console.log("User:", user);
        console.log("Protocol:", protocolRaw);
        console.log("Adapter:", adapter);
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
        revert("RepayAsset: PROTOCOL_KIND must be AAVE/COMPOUND/MORPHO");
    }
}
