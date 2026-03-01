// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AaveLikeAdapter} from "../../src/adapters/AaveLikeAdapter.sol";
import {CompoundLikeAdapter} from "../../src/adapters/CompoundLikeAdapter.sol";
import {MorphoLikeAdapter} from "../../src/adapters/MorphoLikeAdapter.sol";
import {AdapterRegistry} from "../../src/reprieve/AdapterRegistry.sol";

/**
 * @title WireAdapters
 * @notice Validates deployed demo adapters and optionally wires them into AdapterRegistry.
 * @dev Also persists adapter addresses into chain config JSON.
 */
contract WireAdapters is Script {
    function run() external {
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(ownerPrivateKey);

        string memory configPath = _configPath();
        string memory json = vm.readFile(configPath);

        address collateral = _envOrConfigAddress("COLLATERAL_ASSET", json, ".contracts.MockERC20_Collateral");
        address debt = _envOrConfigAddress("DEBT_ASSET", json, ".contracts.MockERC20_Debt");
        address aaveAdapterAddr = _envOrConfigAddress("AAVE_ADAPTER", json, ".contracts.AaveLikeAdapter");
        address compoundAdapterAddr =
            _envOrConfigAddress("COMPOUND_ADAPTER", json, ".contracts.CompoundLikeAdapter");
        address morphoAdapterAddr = _envOrConfigAddress("MORPHO_ADAPTER", json, ".contracts.MorphoLikeAdapter");
        address registryAddr = vm.envOr("ADAPTER_REGISTRY", address(0));

        require(collateral != address(0), "WireAdapters: missing collateral");
        require(debt != address(0), "WireAdapters: missing debt");
        require(aaveAdapterAddr != address(0), "WireAdapters: missing AAVE_ADAPTER");
        require(compoundAdapterAddr != address(0), "WireAdapters: missing COMPOUND_ADAPTER");
        require(morphoAdapterAddr != address(0), "WireAdapters: missing MORPHO_ADAPTER");

        console.log("Wiring adapters as owner:", owner);
        console.log("AaveAdapter:", aaveAdapterAddr);
        console.log("CompoundAdapter:", compoundAdapterAddr);
        console.log("MorphoAdapter:", morphoAdapterAddr);
        console.log("Registry (optional):", registryAddr);

        AaveLikeAdapter aaveAdapter = AaveLikeAdapter(aaveAdapterAddr);
        CompoundLikeAdapter compoundAdapter = CompoundLikeAdapter(compoundAdapterAddr);
        MorphoLikeAdapter morphoAdapter = MorphoLikeAdapter(morphoAdapterAddr);

        require(aaveAdapter.supportsPair(collateral, debt), "WireAdapters: Aave pair unsupported");
        require(compoundAdapter.supportsPair(collateral, debt), "WireAdapters: Compound pair unsupported");
        require(morphoAdapter.supportsPair(collateral, debt), "WireAdapters: Morpho pair unsupported");

        if (registryAddr != address(0)) {
            vm.startBroadcast(ownerPrivateKey);
            AdapterRegistry registry = AdapterRegistry(registryAddr);
            registry.setAdapter(registry.AAVE_LIKE(), aaveAdapterAddr);
            registry.setAdapter(registry.COMPOUND_LIKE(), compoundAdapterAddr);
            registry.setAdapter(registry.MORPHO_LIKE(), morphoAdapterAddr);
            vm.stopBroadcast();

            console.log("Registry wired for all protocol IDs.");
        }

        _writeAdapters(configPath, json, aaveAdapterAddr, compoundAdapterAddr, morphoAdapterAddr);
    }

    function _configPath() internal view returns (string memory) {
        string memory path = vm.envOr("CONFIG_PATH", string(""));
        if (bytes(path).length > 0) return path;
        if (block.chainid == 11155111) return "config/ethereum-sepolia.json";
        if (block.chainid == 84532) return "config/base-sepolia.json";
        revert("WireAdapters: CONFIG_PATH required for this chain");
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

    function _writeAdapters(
        string memory configPath,
        string memory json,
        address aaveAdapter,
        address compoundAdapter,
        address morphoAdapter
    ) internal {
        string memory out = string.concat(
            '{"chainId":',
            vm.toString(vm.parseJsonUint(json, ".chainId")),
            ',"chainName":"',
            vm.parseJsonString(json, ".chainName"),
            '","rpcEnvVar":"',
            vm.parseJsonString(json, ".rpcEnvVar"),
            '","deployerEnvVar":"',
            vm.parseJsonString(json, ".deployerEnvVar"),
            '","contracts":{'
        );

        out = string.concat(out, '"MockPriceOracle":"', vm.parseJsonString(json, ".contracts.MockPriceOracle"), '",');
        out = string.concat(out, '"MockERC20_Collateral":"', vm.parseJsonString(json, ".contracts.MockERC20_Collateral"), '",');
        out = string.concat(out, '"MockERC20_Debt":"', vm.parseJsonString(json, ".contracts.MockERC20_Debt"), '",');
        out = string.concat(out, '"MockAavePool":"', vm.parseJsonString(json, ".contracts.MockAavePool"), '",');
        out = string.concat(out, '"MockAToken":"', vm.parseJsonString(json, ".contracts.MockAToken"), '",');
        out = string.concat(out, '"MockCompoundComet":"', vm.parseJsonString(json, ".contracts.MockCompoundComet"), '",');
        out = string.concat(out, '"MockCToken":"', vm.parseJsonString(json, ".contracts.MockCToken"), '",');
        out = string.concat(out, '"MockMorphoMarket":"', vm.parseJsonString(json, ".contracts.MockMorphoMarket"), '",');
        out = string.concat(out, '"MockVaultShare":"', vm.parseJsonString(json, ".contracts.MockVaultShare"), '",');
        out = string.concat(out, '"AaveLikeAdapter":"', vm.toString(aaveAdapter), '",');
        out = string.concat(out, '"CompoundLikeAdapter":"', vm.toString(compoundAdapter), '",');
        out = string.concat(out, '"MorphoLikeAdapter":"', vm.toString(morphoAdapter), '"');
        out = string.concat(out, '},"riskParams":', vm.parseJsonString(json, ".riskParams"));
        out = string.concat(out, ',"tokenParams":', vm.parseJsonString(json, ".tokenParams"), "}");

        vm.writeFile(configPath, out);
        console.log("Config updated:", configPath);
    }
}
