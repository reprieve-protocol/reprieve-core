// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AaveLikeAdapter} from "../../src/adapters/AaveLikeAdapter.sol";
import {CompoundLikeAdapter} from "../../src/adapters/CompoundLikeAdapter.sol";
import {MorphoLikeAdapter} from "../../src/adapters/MorphoLikeAdapter.sol";

/**
 * @title DeployAdapters
 * @notice Deploys Reprieve adapters for protocol mimics
 * @dev Run with: forge script script/demo/DeployAdapters.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract DeployAdapters is Script {
    struct AdapterConfig {
        address aavePool;
        address compoundMarket;
        address morphoMarket;
        address collateralAsset;
        address debtAsset;
        address cToken;
        bytes32 morphoMarketId;
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying adapters from:", deployer);
        
        // Load config from environment or use defaults for anvil
        AdapterConfig memory config = AdapterConfig({
            aavePool: vm.envOr("AAVE_POOL", address(0)),
            compoundMarket: vm.envOr("COMPOUND_MARKET", address(0)),
            morphoMarket: vm.envOr("MORPHO_MARKET", address(0)),
            collateralAsset: vm.envOr("COLLATERAL_ASSET", address(0)),
            debtAsset: vm.envOr("DEBT_ASSET", address(0)),
            cToken: vm.envOr("C_TOKEN", address(0)),
            morphoMarketId: keccak256(abi.encodePacked("DEMO_MARKET"))
        });
        
        require(config.aavePool != address(0), "AAVE_POOL not set");
        require(config.compoundMarket != address(0), "COMPOUND_MARKET not set");
        require(config.morphoMarket != address(0), "MORPHO_MARKET not set");
        require(config.collateralAsset != address(0), "COLLATERAL_ASSET not set");
        require(config.debtAsset != address(0), "DEBT_ASSET not set");
        require(config.cToken != address(0), "C_TOKEN not set");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy Aave adapter
        AaveLikeAdapter aaveAdapter = new AaveLikeAdapter(
            config.aavePool,
            config.collateralAsset,
            config.debtAsset,
            deployer
        );
        console.log("AaveLikeAdapter deployed at:", address(aaveAdapter));
        
        // Deploy Compound adapter
        CompoundLikeAdapter compoundAdapter = new CompoundLikeAdapter(
            config.compoundMarket,
            config.collateralAsset,
            config.debtAsset,
            config.cToken,
            deployer
        );
        console.log("CompoundLikeAdapter deployed at:", address(compoundAdapter));
        
        // Deploy Morpho adapter
        MorphoLikeAdapter morphoAdapter = new MorphoLikeAdapter(
            config.morphoMarket,
            config.collateralAsset,
            config.debtAsset,
            config.morphoMarketId,
            deployer
        );
        console.log("MorphoLikeAdapter deployed at:", address(morphoAdapter));
        
        vm.stopBroadcast();
        
        // Write deployment summary
        console.log("\n=== Adapter Deployment Summary ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("AaveLikeAdapter:", address(aaveAdapter));
        console.log("CompoundLikeAdapter:", address(compoundAdapter));
        console.log("MorphoLikeAdapter:", address(morphoAdapter));
    }
}
