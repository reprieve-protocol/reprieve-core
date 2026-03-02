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
        address existingCollateral = vm.envOr("COLLATERAL_ASSET", address(0));
        address existingDebt = vm.envOr("DEBT_ASSET", address(0));
        address existingOracle = vm.envOr("PRICE_ORACLE", address(0));
        bool setOraclePrices = vm.envOr("SET_ORACLE_PRICES", false);

        console.log("=== DeployLendingStack ===");
        console.log("Chain:", cfg.chainName);
        console.log("Chain ID:", cfg.chainId);
        console.log("Deployer:", deployer);
        console.log("Config:", configPath);

        vm.startBroadcast(deployerPrivateKey);

        // 1) Primitives (deploy or reuse)
        if ((existingCollateral == address(0)) != (existingDebt == address(0))) {
            revert("DeployLendingStack: provide both COLLATERAL_ASSET and DEBT_ASSET");
        }

        address collateralToken;
        address debtToken;
        address oracleAddress;

        if (existingCollateral != address(0)) {
            collateralToken = existingCollateral;
            debtToken = existingDebt;
        } else {
            collateralToken = address(
                new MockERC20(cfg.collateral.name, cfg.collateral.symbol, cfg.collateral.decimals, deployer)
            );
            debtToken = address(new MockERC20(cfg.debt.name, cfg.debt.symbol, cfg.debt.decimals, deployer));
        }

        if (existingOracle != address(0)) {
            oracleAddress = existingOracle;
            if (setOraclePrices) {
                MockPriceOracle(existingOracle).setPrice(collateralToken, cfg.collateral.initialPriceWad);
                MockPriceOracle(existingOracle).setPrice(debtToken, cfg.debt.initialPriceWad);
            }
        } else {
            MockPriceOracle oracle = new MockPriceOracle(deployer, DemoConstants.DEFAULT_STALENESS_THRESHOLD);
            oracle.setPrice(collateralToken, cfg.collateral.initialPriceWad);
            oracle.setPrice(debtToken, cfg.debt.initialPriceWad);
            oracleAddress = address(oracle);
        }

        // 2) Protocol mimics
        MockAavePool aavePool = new MockAavePool(collateralToken, debtToken, oracleAddress, deployer);
        MockCompoundMarket compoundMarket =
            new MockCompoundMarket(collateralToken, debtToken, oracleAddress, deployer);
        MockMorphoMarket morphoMarket = new MockMorphoMarket(collateralToken, debtToken, oracleAddress, deployer);

        // 3) Engine wiring and risk params
        _wireAndSetRisk(aavePool.engine(), address(aavePool), oracleAddress, cfg.risk);
        _wireAndSetRisk(compoundMarket.engine(), address(compoundMarket), oracleAddress, cfg.risk);
        _wireAndSetRisk(morphoMarket.engine(), address(morphoMarket), oracleAddress, cfg.risk);

        // 4) Adapters
        AaveLikeAdapter aaveAdapter =
            new AaveLikeAdapter(address(aavePool), collateralToken, debtToken, deployer);
        CompoundLikeAdapter compoundAdapter = new CompoundLikeAdapter(
            address(compoundMarket), collateralToken, debtToken, address(compoundMarket.cToken()), deployer
        );
        MorphoLikeAdapter morphoAdapter = new MorphoLikeAdapter(
            address(morphoMarket),
            collateralToken,
            debtToken,
            keccak256(abi.encodePacked("DEMO_MARKET")),
            deployer
        );

        vm.stopBroadcast();

        DeployResult memory result = DeployResult({
            mockPriceOracle: oracleAddress,
            collateralToken: collateralToken,
            debtToken: debtToken,
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
        _printSummary(result, existingCollateral != address(0), existingOracle != address(0));
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

    function _printSummary(DeployResult memory r, bool reusedTokens, bool reusedOracle) internal pure {
        console.log("\n=== Lending Stack Summary ===");
        console.log("Reused collateral/debt tokens:", reusedTokens);
        console.log("Reused oracle:", reusedOracle);
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
