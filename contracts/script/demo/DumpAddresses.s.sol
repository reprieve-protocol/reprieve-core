// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AaveLikeAdapter} from "../../src/adapters/AaveLikeAdapter.sol";
import {CompoundLikeAdapter} from "../../src/adapters/CompoundLikeAdapter.sol";
import {MorphoLikeAdapter} from "../../src/adapters/MorphoLikeAdapter.sol";

/**
 * @title DumpAddresses
 * @notice Reads deployed adapter addresses and outputs JSON/TOML formatted config
 * @dev Run with: forge script script/demo/DumpAddresses.s.sol --rpc-url <RPC_URL>
 */
contract DumpAddresses is Script {
    struct DeploymentInfo {
        uint256 chainId;
        address aaveAdapter;
        address compoundAdapter;
        address morphoAdapter;
        address aavePool;
        address compoundMarket;
        address morphoMarket;
        address collateralAsset;
        address debtAsset;
    }

    function run() public view {
        // Load addresses from environment
        DeploymentInfo memory info = DeploymentInfo({
            chainId: block.chainid,
            aaveAdapter: vm.envOr("AAVE_ADAPTER", address(0)),
            compoundAdapter: vm.envOr("COMPOUND_ADAPTER", address(0)),
            morphoAdapter: vm.envOr("MORPHO_ADAPTER", address(0)),
            aavePool: vm.envOr("AAVE_POOL", address(0)),
            compoundMarket: vm.envOr("COMPOUND_MARKET", address(0)),
            morphoMarket: vm.envOr("MORPHO_MARKET", address(0)),
            collateralAsset: vm.envOr("COLLATERAL_ASSET", address(0)),
            debtAsset: vm.envOr("DEBT_ASSET", address(0))
        });
        
        // If adapter addresses are provided, read their protocol addresses
        if (info.aaveAdapter != address(0)) {
            info.aavePool = AaveLikeAdapter(info.aaveAdapter).protocolAddress();
            info.collateralAsset = AaveLikeAdapter(info.aaveAdapter).collateralAsset();
            info.debtAsset = AaveLikeAdapter(info.aaveAdapter).debtAsset();
        }
        
        // Output JSON format
        console.log("\n=== Adapter Deployment JSON ===");
        console.log("{");
        console.log(string.concat('  "chainId": ', vm.toString(info.chainId), ','));
        console.log(string.concat('  "adapters": {'));
        console.log(string.concat('    "aave": "', vm.toString(info.aaveAdapter), '",' ));
        console.log(string.concat('    "compound": "', vm.toString(info.compoundAdapter), '",' ));
        console.log(string.concat('    "morpho": "', vm.toString(info.morphoAdapter), '"' ));
        console.log("  },");
        console.log(string.concat('  "protocols": {'));
        console.log(string.concat('    "aavePool": "', vm.toString(info.aavePool), '",' ));
        console.log(string.concat('    "compoundMarket": "', vm.toString(info.compoundMarket), '",' ));
        console.log(string.concat('    "morphoMarket": "', vm.toString(info.morphoMarket), '"' ));
        console.log("  },");
        console.log(string.concat('  "assets": {'));
        console.log(string.concat('    "collateral": "', vm.toString(info.collateralAsset), '",' ));
        console.log(string.concat('    "debt": "', vm.toString(info.debtAsset), '"' ));
        console.log("  }");
        console.log("}");
        
        // Output TOML format for CRE config
        console.log("\n=== Adapter Deployment TOML ===");
        console.log("[adapters]");
        console.log(string.concat('aave = "', vm.toString(info.aaveAdapter), '"'));
        console.log(string.concat('compound = "', vm.toString(info.compoundAdapter), '"'));
        console.log(string.concat('morpho = "', vm.toString(info.morphoAdapter), '"'));
        console.log("");
        console.log("[protocols]");
        console.log(string.concat('aave_pool = "', vm.toString(info.aavePool), '"'));
        console.log(string.concat('compound_market = "', vm.toString(info.compoundMarket), '"'));
        console.log(string.concat('morpho_market = "', vm.toString(info.morphoMarket), '"'));
        console.log("");
        console.log("[assets]");
        console.log(string.concat('collateral = "', vm.toString(info.collateralAsset), '"'));
        console.log(string.concat('debt = "', vm.toString(info.debtAsset), '"'));
        console.log("");
        console.log("[chain]");
        console.log(string.concat('chain_id = ', vm.toString(info.chainId)));
    }
}
