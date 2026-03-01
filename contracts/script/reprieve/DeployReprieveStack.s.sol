// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AdapterRegistry} from "../../src/reprieve/AdapterRegistry.sol";
import {RescueLog} from "../../src/reprieve/RescueLog.sol";
import {RescueEscrow} from "../../src/reprieve/RescueEscrow.sol";
import {RescueExecutor} from "../../src/reprieve/RescueExecutor.sol";
import {CCIPReceiver} from "../../src/reprieve/CCIPReceiver.sol";
import {HealthMonitor} from "../../src/reprieve/HealthMonitor.sol";

/**
 * @title DeployReprieveStack
 * @notice One-shot deploy + baseline wiring for Reprieve contracts (no CRE phase).
 */
contract DeployReprieveStack is Script {
    struct StackAddresses {
        address adapterRegistry;
        address rescueLog;
        address rescueEscrow;
        address rescueExecutor;
        address ccipReceiver;
        address healthMonitor;
    }

    function run() external {
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(ownerPrivateKey);

        address workflow = vm.envOr("WORKFLOW", address(0));
        address ccipRouter = _resolveRouter();
        (address aaveAdapter, address compoundAdapter, address morphoAdapter) = _resolveAdapters();

        console.log("Deploying Reprieve stack from owner:", owner);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(ownerPrivateKey);

        AdapterRegistry registry = new AdapterRegistry(owner);
        registry.initializeDemoProtocols();

        RescueLog rescueLog = new RescueLog(owner);
        RescueEscrow rescueEscrow = new RescueEscrow(owner, address(rescueLog));
        RescueExecutor rescueExecutor =
            new RescueExecutor(owner, address(rescueLog), address(rescueEscrow), address(registry));
        CCIPReceiver ccipReceiver = new CCIPReceiver(owner, address(rescueExecutor), address(rescueEscrow), address(rescueLog));
        HealthMonitor healthMonitor = new HealthMonitor(owner);

        // Baseline auth wiring
        rescueLog.setAuthorizedWriter(address(rescueExecutor), true);
        rescueLog.setAuthorizedWriter(address(ccipReceiver), true);
        rescueLog.setAuthorizedWriter(address(rescueEscrow), true);
        rescueEscrow.setAuthorizedDepositor(address(rescueExecutor), true);
        rescueEscrow.setAuthorizedDepositor(address(ccipReceiver), true);

        if (workflow != address(0)) {
            rescueExecutor.setAuthorizedWorkflow(workflow, true);
            healthMonitor.setAuthorizedReporter(workflow, true);
        }

        if (ccipRouter != address(0)) {
            rescueExecutor.setCcipRouter(ccipRouter);
            ccipReceiver.setRouter(ccipRouter);
        }

        if (aaveAdapter != address(0)) {
            registry.setAdapter(registry.AAVE_LIKE(), aaveAdapter);
        }
        if (compoundAdapter != address(0)) {
            registry.setAdapter(registry.COMPOUND_LIKE(), compoundAdapter);
        }
        if (morphoAdapter != address(0)) {
            registry.setAdapter(registry.MORPHO_LIKE(), morphoAdapter);
        }

        vm.stopBroadcast();

        StackAddresses memory deployed = StackAddresses({
            adapterRegistry: address(registry),
            rescueLog: address(rescueLog),
            rescueEscrow: address(rescueEscrow),
            rescueExecutor: address(rescueExecutor),
            ccipReceiver: address(ccipReceiver),
            healthMonitor: address(healthMonitor)
        });

        _writeArtifact(deployed, workflow, ccipRouter);

        console.log("\n=== Reprieve Stack Deployment ===");
        console.log("AdapterRegistry:", deployed.adapterRegistry);
        console.log("RescueLog:", deployed.rescueLog);
        console.log("RescueEscrow:", deployed.rescueEscrow);
        console.log("RescueExecutor:", deployed.rescueExecutor);
        console.log("CCIPReceiver:", deployed.ccipReceiver);
        console.log("HealthMonitor:", deployed.healthMonitor);
    }

    function _writeArtifact(StackAddresses memory a, address workflow, address ccipRouter) internal {
        string memory path = string.concat("config/reprieve-stack-", vm.toString(block.chainid), ".json");
        string memory out = string.concat(
            '{"chainId":',
            vm.toString(block.chainid),
            ',"contracts":{"AdapterRegistry":"',
            vm.toString(a.adapterRegistry),
            '","RescueLog":"',
            vm.toString(a.rescueLog),
            '","RescueEscrow":"',
            vm.toString(a.rescueEscrow),
            '","RescueExecutor":"',
            vm.toString(a.rescueExecutor),
            '","CCIPReceiver":"',
            vm.toString(a.ccipReceiver),
            '","HealthMonitor":"',
            vm.toString(a.healthMonitor),
            '"},"wiring":{"workflow":"',
            vm.toString(workflow),
            '","ccipRouter":"',
            vm.toString(ccipRouter),
            '"}}'
        );

        vm.writeFile(path, out);
        console.log("Artifact written:", path);
    }

    function _resolveRouter() internal view returns (address) {
        address router = vm.envOr("CCIP_ROUTER", address(0));
        if (router != address(0)) return router;

        if (block.chainid == 11155111) {
            return vm.envOr("ETHEREUM_SEPOLIA_CCIP_ROUTER", address(0));
        }
        if (block.chainid == 84532) {
            return vm.envOr("BASE_SEPOLIA_CCIP_ROUTER", address(0));
        }
        return address(0);
    }

    function _resolveAdapters() internal view returns (address aave, address compound, address morpho) {
        aave = vm.envOr("AAVE_ADAPTER", address(0));
        compound = vm.envOr("COMPOUND_ADAPTER", address(0));
        morpho = vm.envOr("MORPHO_ADAPTER", address(0));
        if (aave != address(0) && compound != address(0) && morpho != address(0)) {
            return (aave, compound, morpho);
        }

        string memory configPath = _configPath();
        string memory json = vm.readFile(configPath);
        if (aave == address(0)) {
            aave = _parseConfigAddress(json, ".contracts.AaveLikeAdapter");
        }
        if (compound == address(0)) {
            compound = _parseConfigAddress(json, ".contracts.CompoundLikeAdapter");
        }
        if (morpho == address(0)) {
            morpho = _parseConfigAddress(json, ".contracts.MorphoLikeAdapter");
        }
        return (aave, compound, morpho);
    }

    function _configPath() internal view returns (string memory) {
        string memory path = vm.envOr("CONFIG_PATH", string(""));
        if (bytes(path).length > 0) return path;
        if (block.chainid == 11155111) return "config/ethereum-sepolia.json";
        if (block.chainid == 84532) return "config/base-sepolia.json";
        revert("DeployReprieveStack: CONFIG_PATH required for this chain");
    }

    function _parseConfigAddress(string memory json, string memory keyPath) internal view returns (address) {
        string memory raw = vm.parseJsonString(json, keyPath);
        if (bytes(raw).length == 0) return address(0);
        return vm.parseAddress(raw);
    }
}
