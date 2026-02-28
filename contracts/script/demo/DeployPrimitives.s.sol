// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockPriceOracle} from "../../src/mocks/MockPriceOracle.sol";
import {DemoConstants} from "../../src/libs/DemoConstants.sol";

/**
 * @title DeployPrimitives
 * @notice Deployment script for Slide 1: Core Primitives
 * @dev Deploys MockERC20 tokens (collateral + debt) and MockPriceOracle
 * @dev Uses config file for chain-specific parameters
 */
contract DeployPrimitives is Script {
    
    struct TokenConfig {
        string name;
        string symbol;
        uint8 decimals;
        uint256 initialPriceWad;
    }
    
    struct DeployConfig {
        uint256 chainId;
        string chainName;
        TokenConfig collateral;
        TokenConfig debt;
    }
    
    // Events
    event PrimitivesDeployed(
        address indexed collateralToken,
        address indexed debtToken,
        address indexed oracle,
        uint256 stalenessThreshold
    );
    
    /**
     * @notice Read deployment config from JSON file
     * @param configPath Path to config file
     */
    function readConfig(string memory configPath) internal view returns (DeployConfig memory) {
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
            })
        });
    }
    
    /**
     * @notice Deploy primitives (tokens + oracle)
     * @param configPath Path to chain config file
     * @param minter Address with mint/burn privileges (typically deployer or protocol admin)
     */
    function deploy(string memory configPath, address minter) internal returns (
        MockERC20 collateralToken,
        MockERC20 debtToken,
        MockPriceOracle oracle
    ) {
        require(minter != address(0), "DeployPrimitives: minter cannot be zero");
        
        DeployConfig memory cfg = readConfig(configPath);
        
        console.log("========================================");
        console.log("Deploying Primitives");
        console.log("Chain:", cfg.chainName);
        console.log("Chain ID:", cfg.chainId);
        console.log("========================================");
        
        // Deploy collateral token
        collateralToken = new MockERC20(
            cfg.collateral.name,
            cfg.collateral.symbol,
            cfg.collateral.decimals,
            minter
        );
        console.log("Collateral Token deployed:");
        console.log("  Address:", address(collateralToken));
        console.log("  Name:", cfg.collateral.name);
        console.log("  Symbol:", cfg.collateral.symbol);
        console.log("  Decimals:", cfg.collateral.decimals);
        
        // Deploy debt token
        debtToken = new MockERC20(
            cfg.debt.name,
            cfg.debt.symbol,
            cfg.debt.decimals,
            minter
        );
        console.log("Debt Token deployed:");
        console.log("  Address:", address(debtToken));
        console.log("  Name:", cfg.debt.name);
        console.log("  Symbol:", cfg.debt.symbol);
        console.log("  Decimals:", cfg.debt.decimals);
        
        // Deploy oracle
        address oracleOwner = msg.sender;
        oracle = new MockPriceOracle(
            oracleOwner,
            DemoConstants.DEFAULT_STALENESS_THRESHOLD
        );
        console.log("Price Oracle deployed:");
        console.log("  Address:", address(oracle));
        console.log("  Owner:", oracleOwner);
        console.log("  Staleness Threshold:", DemoConstants.DEFAULT_STALENESS_THRESHOLD, "seconds");
        
        // Set initial prices
        oracle.setPrice(address(collateralToken), cfg.collateral.initialPriceWad);
        oracle.setPrice(address(debtToken), cfg.debt.initialPriceWad);
        console.log("Initial prices set:");
        console.log("  Collateral:", cfg.collateral.initialPriceWad, "(WAD)");
        console.log("  Debt:", cfg.debt.initialPriceWad, "(WAD)");
        
        emit PrimitivesDeployed(
            address(collateralToken),
            address(debtToken),
            address(oracle),
            DemoConstants.DEFAULT_STALENESS_THRESHOLD
        );
        
        console.log("========================================");
        console.log("Deployment Complete");
        console.log("========================================");
        
        return (collateralToken, debtToken, oracle);
    }
    
    /**
     * @notice Run deployment for Arbitrum Sepolia
     */
    function runArbitrumSepolia() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        vm.startBroadcast(deployer);
        
        (MockERC20 collateral, MockERC20 debt, MockPriceOracle oracle) = 
            deploy("config/arbitrum-sepolia.json", deployer);
        
        vm.stopBroadcast();
        
        // Write deployed addresses back to config
        writeAddresses("config/arbitrum-sepolia.json", collateral, debt, oracle);
    }
    
    /**
     * @notice Run deployment for Base Sepolia
     */
    function runBaseSepolia() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        vm.startBroadcast(deployer);
        
        (MockERC20 collateral, MockERC20 debt, MockPriceOracle oracle) = 
            deploy("config/base-sepolia.json", deployer);
        
        vm.stopBroadcast();
        
        // Write deployed addresses back to config
        writeAddresses("config/base-sepolia.json", collateral, debt, oracle);
    }
    
    /**
     * @notice Run deployment (generic - uses ARBITRUM_SEPOLIA_RPC by default)
     */
    function run() external {
        address deployer = msg.sender;
        
        vm.startBroadcast();
        
        (MockERC20 collateral, MockERC20 debt, MockPriceOracle oracle) = 
            deploy("config/arbitrum-sepolia.json", deployer);
        
        vm.stopBroadcast();
        
        // Log addresses for local testing
        console.log("Deployed addresses (local):");
        console.log("  Collateral:", address(collateral));
        console.log("  Debt:", address(debt));
        console.log("  Oracle:", address(oracle));
    }
    
    /**
     * @notice Write deployed addresses to config file
     */
    function writeAddresses(
        string memory configPath,
        MockERC20 collateral,
        MockERC20 debt,
        MockPriceOracle oracle
    ) internal {
        // Read existing config
        string memory json = vm.readFile(configPath);
        
        // Build updated JSON
        string memory output = "{\"chainId\":";
        output = string.concat(output, vm.toString(vm.parseJsonUint(json, ".chainId")));
        output = string.concat(output, ",\"chainName\":\"");
        output = string.concat(output, vm.parseJsonString(json, ".chainName"));
        output = string.concat(output, "\",\"rpcEnvVar\":\"");
        output = string.concat(output, vm.parseJsonString(json, ".rpcEnvVar"));
        output = string.concat(output, "\",\"deployerEnvVar\":\"");
        output = string.concat(output, vm.parseJsonString(json, ".deployerEnvVar"));
        output = string.concat(output, "\",\"contracts\":{");
        output = string.concat(output, "\"MockPriceOracle\":\"");
        output = string.concat(output, vm.toString(address(oracle)));
        output = string.concat(output, "\",\"MockERC20_Collateral\":\"");
        output = string.concat(output, vm.toString(address(collateral)));
        output = string.concat(output, "\",\"MockERC20_Debt\":\"");
        output = string.concat(output, vm.toString(address(debt)));
        output = string.concat(output, "\"},\"riskParams\":");
        output = string.concat(output, vm.parseJsonString(json, ".riskParams"));
        output = string.concat(output, ",\"tokenParams\":");
        output = string.concat(output, vm.parseJsonString(json, ".tokenParams"));
        output = string.concat(output, "}");
        
        vm.writeFile(configPath, output);
        console.log("Addresses written to:", configPath);
    }
}
