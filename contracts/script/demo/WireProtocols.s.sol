// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockAavePool} from "../../src/mocks/MockAavePool.sol";
import {MockCompoundMarket} from "../../src/mocks/MockCompoundMarket.sol";
import {MockMorphoMarket} from "../../src/mocks/MockMorphoMarket.sol";
import {BaseLendingEngine} from "../../src/mocks/BaseLendingEngine.sol";

/**
 * @title WireProtocols
 * @notice Wires oracle + operator permissions on deployed protocol mimic engines.
 * @dev Ensures each market contract is authorized to act on behalf of users in its engine.
 */
contract WireProtocols is Script {
    function run() external {
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(ownerPrivateKey);

        string memory configPath = _configPath();
        string memory json = vm.readFile(configPath);

        address oracle = _envOrConfigAddress("PRICE_ORACLE", json, ".contracts.MockPriceOracle");
        address aavePoolAddr = _envOrConfigAddress("AAVE_POOL", json, ".contracts.MockAavePool");
        address compoundAddr = _envOrConfigAddress("COMPOUND_MARKET", json, ".contracts.MockCompoundComet");
        address morphoAddr = _envOrConfigAddress("MORPHO_MARKET", json, ".contracts.MockMorphoMarket");

        require(oracle != address(0), "WireProtocols: missing oracle");
        require(aavePoolAddr != address(0), "WireProtocols: missing AAVE_POOL");
        require(compoundAddr != address(0), "WireProtocols: missing COMPOUND_MARKET");
        require(morphoAddr != address(0), "WireProtocols: missing MORPHO_MARKET");

        MockAavePool aave = MockAavePool(aavePoolAddr);
        MockCompoundMarket compound = MockCompoundMarket(compoundAddr);
        MockMorphoMarket morpho = MockMorphoMarket(morphoAddr);

        BaseLendingEngine aaveEngine = aave.engine();
        BaseLendingEngine compoundEngine = compound.engine();
        BaseLendingEngine morphoEngine = morpho.engine();

        console.log("Wiring protocol engines as owner:", owner);
        console.log("AavePool:", aavePoolAddr);
        console.log("CompoundMarket:", compoundAddr);
        console.log("MorphoMarket:", morphoAddr);
        console.log("Oracle:", oracle);

        vm.startBroadcast(ownerPrivateKey);

        _wireEngine(aaveEngine, aavePoolAddr, oracle);
        _wireEngine(compoundEngine, compoundAddr, oracle);
        _wireEngine(morphoEngine, morphoAddr, oracle);

        vm.stopBroadcast();

        console.log("Protocol wiring complete.");
    }

    function _wireEngine(BaseLendingEngine engine, address operator, address oracle) internal {
        if (engine.oracle() != oracle) {
            engine.setOracle(oracle);
        }
        if (!engine.authorizedOperators(operator)) {
            engine.setAuthorizedOperator(operator, true);
        }
    }

    function _configPath() internal view returns (string memory) {
        string memory path = vm.envOr("CONFIG_PATH", string(""));
        if (bytes(path).length > 0) return path;
        if (block.chainid == 11155111) return "config/ethereum-sepolia.json";
        if (block.chainid == 84532) return "config/base-sepolia.json";
        revert("WireProtocols: CONFIG_PATH required for this chain");
    }

    function _envOrConfigAddress(
        string memory envKey,
        string memory json,
        string memory jsonPath
    ) internal view returns (address) {
        address fromEnv = vm.envOr(envKey, address(0));
        if (fromEnv != address(0)) return fromEnv;

        string memory raw = vm.parseJsonString(json, jsonPath);
        if (bytes(raw).length == 0) return address(0);
        return vm.parseAddress(raw);
    }
}
