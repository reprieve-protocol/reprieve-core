// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockPriceOracle} from "../../src/mocks/MockPriceOracle.sol";
import {MockAavePool} from "../../src/mocks/MockAavePool.sol";
import {MockCompoundMarket} from "../../src/mocks/MockCompoundMarket.sol";
import {MockMorphoMarket} from "../../src/mocks/MockMorphoMarket.sol";
import {AaveLikeAdapter} from "../../src/adapters/AaveLikeAdapter.sol";
import {CompoundLikeAdapter} from "../../src/adapters/CompoundLikeAdapter.sol";
import {MorphoLikeAdapter} from "../../src/adapters/MorphoLikeAdapter.sol";
import {BaseLendingEngine} from "../../src/mocks/BaseLendingEngine.sol";
import {DemoConstants} from "../../src/libs/DemoConstants.sol";

/**
 * @title DeployLendingStack
 * @notice One-shot deploy for demo lending stack on one chain.
 * @dev Deploys primitives, protocol mimics, wiring, risk params, and adapters.
 */
contract DeployLendingStack is Script {
    struct TokenConfig {
        string name;
        string symbol;
        uint8 decimals;
        uint256 initialPriceWad;
    }

    struct RiskConfig {
        uint256 maxLtvBps;
        uint256 liquidationThresholdBps;
        uint256 liquidationBonusBps;
        uint256 borrowAprBps;
    }

    struct DeployConfig {
        uint256 chainId;
        string chainName;
        TokenConfig collateral;
        TokenConfig debt;
        RiskConfig risk;
    }

    struct DeployResult {
        address mockPriceOracle;
        address collateralToken;
        address debtToken;
        address mockAavePool;
        address mockAToken;
        address mockCompoundComet;
        address mockCToken;
        address mockMorphoMarket;
        address mockVaultShare;
        address aaveLikeAdapter;
        address compoundLikeAdapter;
        address morphoLikeAdapter;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        string memory configPath = _configPath();
        DeployConfig memory cfg = _readConfig(configPath);

        console.log("=== DeployLendingStack ===");
        console.log("Chain:", cfg.chainName);
        console.log("Chain ID:", cfg.chainId);
        console.log("Deployer:", deployer);
        console.log("Config:", configPath);

        vm.startBroadcast(deployerPrivateKey);

        // 1) Primitives
        MockERC20 collateral = new MockERC20(
            cfg.collateral.name, cfg.collateral.symbol, cfg.collateral.decimals, deployer
        );
        MockERC20 debt = new MockERC20(cfg.debt.name, cfg.debt.symbol, cfg.debt.decimals, deployer);
        MockPriceOracle oracle = new MockPriceOracle(deployer, DemoConstants.DEFAULT_STALENESS_THRESHOLD);
        oracle.setPrice(address(collateral), cfg.collateral.initialPriceWad);
        oracle.setPrice(address(debt), cfg.debt.initialPriceWad);

        // 2) Protocol mimics
        MockAavePool aavePool = new MockAavePool(address(collateral), address(debt), address(oracle), deployer);
        MockCompoundMarket compoundMarket =
            new MockCompoundMarket(address(collateral), address(debt), address(oracle), deployer);
        MockMorphoMarket morphoMarket = new MockMorphoMarket(address(collateral), address(debt), address(oracle), deployer);

        // 3) Engine wiring and risk params
        _wireAndSetRisk(aavePool.engine(), address(aavePool), address(oracle), cfg.risk);
        _wireAndSetRisk(compoundMarket.engine(), address(compoundMarket), address(oracle), cfg.risk);
        _wireAndSetRisk(morphoMarket.engine(), address(morphoMarket), address(oracle), cfg.risk);

        // 4) Adapters
        AaveLikeAdapter aaveAdapter =
            new AaveLikeAdapter(address(aavePool), address(collateral), address(debt), deployer);
        CompoundLikeAdapter compoundAdapter = new CompoundLikeAdapter(
            address(compoundMarket), address(collateral), address(debt), address(compoundMarket.cToken()), deployer
        );
        MorphoLikeAdapter morphoAdapter = new MorphoLikeAdapter(
            address(morphoMarket),
            address(collateral),
            address(debt),
            keccak256(abi.encodePacked("DEMO_MARKET")),
            deployer
        );

        vm.stopBroadcast();

        DeployResult memory result = DeployResult({
            mockPriceOracle: address(oracle),
            collateralToken: address(collateral),
            debtToken: address(debt),
            mockAavePool: address(aavePool),
            mockAToken: address(aavePool.aToken()),
            mockCompoundComet: address(compoundMarket),
            mockCToken: address(compoundMarket.cToken()),
            mockMorphoMarket: address(morphoMarket),
            mockVaultShare: address(morphoMarket.vaultShare()),
            aaveLikeAdapter: address(aaveAdapter),
            compoundLikeAdapter: address(compoundAdapter),
            morphoLikeAdapter: address(morphoAdapter)
        });

        _writeConfig(configPath, cfg, result);
        _printSummary(result);
    }

    function _wireAndSetRisk(BaseLendingEngine engine, address operator, address oracle, RiskConfig memory risk) internal {
        if (engine.oracle() != oracle) {
            engine.setOracle(oracle);
        }
        if (!engine.authorizedOperators(operator)) {
            engine.setAuthorizedOperator(operator, true);
        }
        engine.setRiskParams(
            risk.maxLtvBps, risk.liquidationThresholdBps, risk.liquidationBonusBps, risk.borrowAprBps
        );
    }

    function _configPath() internal view returns (string memory) {
        string memory path = vm.envOr("CONFIG_PATH", string(""));
        if (bytes(path).length > 0) return path;
        if (block.chainid == 11155111) return "config/ethereum-sepolia.json";
        if (block.chainid == 84532) return "config/base-sepolia.json";
        revert("DeployLendingStack: CONFIG_PATH required for this chain");
    }

    function _readConfig(string memory configPath) internal view returns (DeployConfig memory) {
        string memory json = vm.readFile(configPath);
        return DeployConfig({
            chainId: vm.parseJsonUint(json, ".chainId"),
            chainName: vm.parseJsonString(json, ".chainName"),
            collateral: TokenConfig({
                name: vm.parseJsonString(json, ".tokenParams.collateral.name"),
                symbol: vm.parseJsonString(json, ".tokenParams.collateral.symbol"),
                decimals: uint8(vm.parseJsonUint(json, ".tokenParams.collateral.decimals")),
                initialPriceWad: vm.parseJsonUint(json, ".tokenParams.collateral.initialPriceWad")
            }),
            debt: TokenConfig({
                name: vm.parseJsonString(json, ".tokenParams.debt.name"),
                symbol: vm.parseJsonString(json, ".tokenParams.debt.symbol"),
                decimals: uint8(vm.parseJsonUint(json, ".tokenParams.debt.decimals")),
                initialPriceWad: vm.parseJsonUint(json, ".tokenParams.debt.initialPriceWad")
            }),
            risk: RiskConfig({
                maxLtvBps: vm.parseJsonUint(json, ".riskParams.maxLtvBps"),
                liquidationThresholdBps: vm.parseJsonUint(json, ".riskParams.liquidationThresholdBps"),
                liquidationBonusBps: vm.parseJsonUint(json, ".riskParams.liquidationBonusBps"),
                borrowAprBps: vm.parseJsonUint(json, ".riskParams.borrowAprBps")
            })
        });
    }

    function _writeConfig(string memory configPath, DeployConfig memory cfg, DeployResult memory r) internal {
        string memory output = string.concat(
            '{"chainId":',
            vm.toString(cfg.chainId),
            ',"chainName":"',
            cfg.chainName,
            '","rpcEnvVar":"',
            block.chainid == 11155111 ? "ETHEREUM_SEPOLIA_RPC" : "BASE_SEPOLIA_RPC",
            '","deployerEnvVar":"',
            block.chainid == 11155111 ? "ETHEREUM_SEPOLIA_DEPLOYER_KEY" : "BASE_SEPOLIA_DEPLOYER_KEY",
            '","contracts":{'
        );

        output = string.concat(output, '"MockPriceOracle":"', vm.toString(r.mockPriceOracle), '",');
        output = string.concat(output, '"MockERC20_Collateral":"', vm.toString(r.collateralToken), '",');
        output = string.concat(output, '"MockERC20_Debt":"', vm.toString(r.debtToken), '",');
        output = string.concat(output, '"MockAavePool":"', vm.toString(r.mockAavePool), '",');
        output = string.concat(output, '"MockAToken":"', vm.toString(r.mockAToken), '",');
        output = string.concat(output, '"MockCompoundComet":"', vm.toString(r.mockCompoundComet), '",');
        output = string.concat(output, '"MockCToken":"', vm.toString(r.mockCToken), '",');
        output = string.concat(output, '"MockMorphoMarket":"', vm.toString(r.mockMorphoMarket), '",');
        output = string.concat(output, '"MockVaultShare":"', vm.toString(r.mockVaultShare), '",');
        output = string.concat(output, '"AaveLikeAdapter":"', vm.toString(r.aaveLikeAdapter), '",');
        output = string.concat(output, '"CompoundLikeAdapter":"', vm.toString(r.compoundLikeAdapter), '",');
        output = string.concat(output, '"MorphoLikeAdapter":"', vm.toString(r.morphoLikeAdapter), '"');
        output = string.concat(output, '},"riskParams":{');
        output = string.concat(output, '"maxLtvBps":', vm.toString(cfg.risk.maxLtvBps), ',');
        output = string.concat(output, '"liquidationThresholdBps":', vm.toString(cfg.risk.liquidationThresholdBps), ',');
        output = string.concat(output, '"liquidationBonusBps":', vm.toString(cfg.risk.liquidationBonusBps), ',');
        output = string.concat(output, '"borrowAprBps":', vm.toString(cfg.risk.borrowAprBps), "},");
        output = string.concat(output, '"tokenParams":{"collateral":{');
        output = string.concat(output, '"name":"', cfg.collateral.name, '",');
        output = string.concat(output, '"symbol":"', cfg.collateral.symbol, '",');
        output = string.concat(output, '"decimals":', vm.toString(uint256(cfg.collateral.decimals)), ',');
        output = string.concat(output, '"initialPriceWad":"', vm.toString(cfg.collateral.initialPriceWad), '"},');
        output = string.concat(output, '"debt":{');
        output = string.concat(output, '"name":"', cfg.debt.name, '",');
        output = string.concat(output, '"symbol":"', cfg.debt.symbol, '",');
        output = string.concat(output, '"decimals":', vm.toString(uint256(cfg.debt.decimals)), ',');
        output = string.concat(output, '"initialPriceWad":"', vm.toString(cfg.debt.initialPriceWad), '"}}}');

        vm.writeFile(configPath, output);
        console.log("Config updated:", configPath);
    }

    function _printSummary(DeployResult memory r) internal view {
        console.log("\n=== Lending Stack Summary ===");
        console.log("MockPriceOracle:", r.mockPriceOracle);
        console.log("MockERC20_Collateral:", r.collateralToken);
        console.log("MockERC20_Debt:", r.debtToken);
        console.log("MockAavePool:", r.mockAavePool);
        console.log("MockAToken:", r.mockAToken);
        console.log("MockCompoundComet:", r.mockCompoundComet);
        console.log("MockCToken:", r.mockCToken);
        console.log("MockMorphoMarket:", r.mockMorphoMarket);
        console.log("MockVaultShare:", r.mockVaultShare);
        console.log("AaveLikeAdapter:", r.aaveLikeAdapter);
        console.log("CompoundLikeAdapter:", r.compoundLikeAdapter);
        console.log("MorphoLikeAdapter:", r.morphoLikeAdapter);
    }
}
