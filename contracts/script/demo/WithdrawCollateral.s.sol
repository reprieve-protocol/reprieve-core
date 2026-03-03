// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockAavePool} from "../../src/mocks/MockAavePool.sol";
import {MockCompoundMarket} from "../../src/mocks/MockCompoundMarket.sol";
import {MockMorphoMarket} from "../../src/mocks/MockMorphoMarket.sol";
import {BaseLendingEngine} from "../../src/mocks/BaseLendingEngine.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IReprieveAdapter} from "../../src/interfaces/IReprieveAdapter.sol";

interface IOracleLike {
    function getPrice(address asset) external view returns (uint256 price, uint256 timestamp);
}

/**
 * @title WithdrawCollateral
 * @notice User action: withdraw collateral from selected protocol market.
 * @dev For MORPHO mock, withdrawal is executed via underlying engine directly.
 */
contract WithdrawCollateral is Script {
    function run() external {
        uint256 fallbackPk = vm.envUint("PRIVATE_KEY");
        uint256 userPk = vm.envOr("USER_PRIVATE_KEY", fallbackPk);
        address user = vm.addr(userPk);

        address adapter = vm.envAddress("ADAPTER_ADDRESS");
        address market = vm.envAddress("MARKET_ADDRESS");
        address asset = vm.envAddress("ASSET_ADDRESS");
        uint256 amount = vm.envUint("AMOUNT_RAW");
        string memory protocolRaw = vm.envString("PROTOCOL_KIND");
        string memory symbol = vm.envOr("ASSET_SYMBOL", string(""));
        string memory amountHuman = vm.envOr("AMOUNT_HUMAN", string(""));

        require(adapter != address(0), "WithdrawCollateral: ADAPTER_ADDRESS missing");
        require(market != address(0), "WithdrawCollateral: MARKET_ADDRESS missing");
        require(asset != address(0), "WithdrawCollateral: ASSET_ADDRESS missing");
        require(amount > 0, "WithdrawCollateral: AMOUNT_RAW must be > 0");

        bytes32 protocol = _parseProtocol(protocolRaw);

        BaseLendingEngine engine = _engineForProtocol(market, protocol);
        (uint256 oraclePrice,) = IOracleLike(engine.oracle()).getPrice(asset);
        BaseLendingEngine.Position memory userPositionBefore = engine.getUserPosition(user);

        console.log("Withdraw pre-check:");
        console.log("  User collateral before (raw):", userPositionBefore.collateral);
        console.log("  User debt before (raw):", userPositionBefore.debt);
        console.log("  Oracle price (wad):", oraclePrice);
        console.log("  Requested withdraw (raw):", amount);
        
        vm.startBroadcast(userPk);
        if (protocol == keccak256("AAVE")) {
            require(asset == MockAavePool(market).collateral(), "WithdrawCollateral: non-collateral asset for AAVE");
            address aToken = address(MockAavePool(market).aToken());
            IERC20(aToken).approve(adapter, amount);
            IReprieveAdapter(adapter).withdrawForRescue(user, asset, amount, user);
        } else if (protocol == keccak256("COMPOUND")) {
            require(
                asset == MockCompoundMarket(market).collateral(),
                "WithdrawCollateral: non-collateral asset for Compound"
            );
            // Compound adapter withdraw path redeems against market caller state; for user withdrawals in this mock,
            // route through engine on-behalf path from the user account.
            vm.stopBroadcast();
            vm.startBroadcast(fallbackPk);
            engine.setAuthorizedOperator(user, true);
            vm.stopBroadcast();

            vm.startBroadcast(userPk);
            engine.withdrawOnBehalfOf(user, asset, amount, user);
            vm.stopBroadcast();

            vm.startBroadcast(fallbackPk);
            engine.setAuthorizedOperator(user, false);
            vm.stopBroadcast();
            vm.startBroadcast(userPk);
        } else if (protocol == keccak256("MORPHO")) {
            require(
                asset == MockMorphoMarket(market).collateral(),
                "WithdrawCollateral: non-collateral asset for Morpho"
            );
            MockMorphoMarket(market).engine().withdraw(asset, amount, user);
        } else {
            revert("WithdrawCollateral: unsupported protocol");
        }
        vm.stopBroadcast();

        console.log("Withdraw collateral executed.");
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
        revert("WithdrawCollateral: PROTOCOL_KIND must be AAVE/COMPOUND/MORPHO");
    }

    function _engineForProtocol(address market, bytes32 protocol) internal view returns (BaseLendingEngine) {
        if (protocol == keccak256("AAVE")) {
            return MockAavePool(market).engine();
        }
        if (protocol == keccak256("COMPOUND")) {
            return MockCompoundMarket(market).engine();
        }
        if (protocol == keccak256("MORPHO")) {
            return MockMorphoMarket(market).engine();
        }
        revert("WithdrawCollateral: unsupported protocol");
    }
}
