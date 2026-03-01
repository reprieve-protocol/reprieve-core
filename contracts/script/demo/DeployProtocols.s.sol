// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockAavePool} from "../../src/mocks/MockAavePool.sol";
import {MockCompoundMarket} from "../../src/mocks/MockCompoundMarket.sol";
import {MockMorphoMarket} from "../../src/mocks/MockMorphoMarket.sol";

/**
 * @title DeployProtocols
 * @notice Deploy protocol mimic contracts (Aave/Compound/Morpho) for demo lending.
 * @dev Reads asset/oracle addresses from env vars first, then falls back to chain config JSON.
 */
contract DeployProtocols is Script {
    struct DeployResult {
        address aavePool;
        address aToken;
        address compoundMarket;
        address cToken;
        address morphoMarket;
        address vaultShare;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        string memory configPath = _configPath();
        string memory json = vm.readFile(configPath);

        address collateral = _envOrConfigAddress(
            "COLLATERAL_ASSET",
            json,
            ".contracts.MockERC20_Collateral"
        );
        address debt = _envOrConfigAddress(
            "DEBT_ASSET",
            json,
            ".contracts.MockERC20_Debt"
        );
        address oracle = _envOrConfigAddress(
            "PRICE_ORACLE",
            json,
            ".contracts.MockPriceOracle"
        );

        require(collateral != address(0), "DeployProtocols: collateral missing");
        require(debt != address(0), "DeployProtocols: debt missing");
        require(oracle != address(0), "DeployProtocols: oracle missing");

        console.log("Deploying protocol mocks from:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("Config:", configPath);
        console.log("Collateral:", collateral);
        console.log("Debt:", debt);
        console.log("Oracle:", oracle);

        vm.startBroadcast(deployerPrivateKey);

        MockAavePool aavePool = new MockAavePool(collateral, debt, oracle, deployer);
        MockCompoundMarket compoundMarket = new MockCompoundMarket(collateral, debt, oracle, deployer);
        MockMorphoMarket morphoMarket = new MockMorphoMarket(collateral, debt, oracle, deployer);

        vm.stopBroadcast();

        DeployResult memory result = DeployResult({
            aavePool: address(aavePool),
            aToken: address(aavePool.aToken()),
            compoundMarket: address(compoundMarket),
            cToken: address(compoundMarket.cToken()),
            morphoMarket: address(morphoMarket),
            vaultShare: address(morphoMarket.vaultShare())
        });

        _writeProtocolAddresses(configPath, json, result);

        console.log("\n=== Protocol Deployment Summary ===");
        console.log("MockAavePool:", result.aavePool);
        console.log("MockAToken:", result.aToken);
        console.log("MockCompoundComet:", result.compoundMarket);
        console.log("MockCToken:", result.cToken);
        console.log("MockMorphoMarket:", result.morphoMarket);
        console.log("MockVaultShare:", result.vaultShare);
    }

    function _configPath() internal view returns (string memory) {
        string memory path = vm.envOr("CONFIG_PATH", string(""));
        if (bytes(path).length > 0) return path;
        if (block.chainid == 11155111) return "config/ethereum-sepolia.json";
        if (block.chainid == 84532) return "config/base-sepolia.json";
        revert("DeployProtocols: CONFIG_PATH required for this chain");
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

    function _writeProtocolAddresses(
        string memory configPath,
        string memory json,
        DeployResult memory deployed
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
        out = string.concat(out, '"MockAavePool":"', vm.toString(deployed.aavePool), '",');
        out = string.concat(out, '"MockAToken":"', vm.toString(deployed.aToken), '",');
        out = string.concat(out, '"MockCompoundComet":"', vm.toString(deployed.compoundMarket), '",');
        out = string.concat(out, '"MockCToken":"', vm.toString(deployed.cToken), '",');
        out = string.concat(out, '"MockMorphoMarket":"', vm.toString(deployed.morphoMarket), '",');
        out = string.concat(out, '"MockVaultShare":"', vm.toString(deployed.vaultShare), '",');
        out = string.concat(out, '"AaveLikeAdapter":"', vm.parseJsonString(json, ".contracts.AaveLikeAdapter"), '",');
        out = string.concat(out, '"CompoundLikeAdapter":"', vm.parseJsonString(json, ".contracts.CompoundLikeAdapter"), '",');
        out = string.concat(out, '"MorphoLikeAdapter":"', vm.parseJsonString(json, ".contracts.MorphoLikeAdapter"), '"');
        out = string.concat(out, '},"riskParams":', vm.parseJsonString(json, ".riskParams"));
        out = string.concat(out, ',"tokenParams":', vm.parseJsonString(json, ".tokenParams"), "}");

        vm.writeFile(configPath, out);
        console.log("Config updated:", configPath);
    }
}
