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
 * @title VerifyReprieveStack
 * @notice Verifies post-deploy role wiring and core references for Reprieve stack.
 */
contract VerifyReprieveStack is Script {
    function run() external view {
        address registryAddr = vm.envAddress("ADAPTER_REGISTRY");
        address rescueLogAddr = vm.envAddress("RESCUE_LOG");
        address rescueEscrowAddr = vm.envAddress("RESCUE_ESCROW");
        address rescueExecutorAddr = vm.envAddress("RESCUE_EXECUTOR");
        address ccipReceiverAddr = vm.envAddress("CCIP_RECEIVER");

        address healthMonitorAddr = vm.envOr("HEALTH_MONITOR", address(0));
        address workflow = vm.envOr("WORKFLOW", address(0));
        address reporter = vm.envOr("REPORTER", address(0));
        address ccipRouter = vm.envOr("CCIP_ROUTER", address(0));
        address aaveAdapter = vm.envOr("AAVE_ADAPTER", address(0));
        address compoundAdapter = vm.envOr("COMPOUND_ADAPTER", address(0));
        address morphoAdapter = vm.envOr("MORPHO_ADAPTER", address(0));
        uint64 destSelector = uint64(vm.envOr("DEST_CHAIN_SELECTOR", uint256(0)));
        address destReceiver = vm.envOr("DEST_RECEIVER", address(0));
        uint64 sourceSelector = uint64(vm.envOr("SOURCE_CHAIN_SELECTOR", uint256(0)));
        address sourceSender = vm.envOr("SOURCE_SENDER", address(0));

        AdapterRegistry registry = AdapterRegistry(registryAddr);
        RescueLog rescueLog = RescueLog(rescueLogAddr);
        RescueEscrow rescueEscrow = RescueEscrow(rescueEscrowAddr);
        RescueExecutor rescueExecutor = RescueExecutor(payable(rescueExecutorAddr));
        CCIPReceiver ccipReceiver = CCIPReceiver(payable(ccipReceiverAddr));

        // Core references
        require(address(rescueExecutor.rescueLog()) == rescueLogAddr, "Verify: executor->log mismatch");
        require(address(rescueExecutor.rescueEscrow()) == rescueEscrowAddr, "Verify: executor->escrow mismatch");
        require(address(rescueExecutor.adapterRegistry()) == registryAddr, "Verify: executor->registry mismatch");
        require(address(ccipReceiver.executor()) == rescueExecutorAddr, "Verify: receiver->executor mismatch");
        require(address(ccipReceiver.rescueEscrow()) == rescueEscrowAddr, "Verify: receiver->escrow mismatch");
        require(address(ccipReceiver.rescueLog()) == rescueLogAddr, "Verify: receiver->log mismatch");

        // Protocol support and adapter mappings
        require(registry.isSupportedProtocol(registry.AAVE_LIKE()), "Verify: AAVE_LIKE unsupported");
        require(registry.isSupportedProtocol(registry.COMPOUND_LIKE()), "Verify: COMPOUND_LIKE unsupported");
        require(registry.isSupportedProtocol(registry.MORPHO_LIKE()), "Verify: MORPHO_LIKE unsupported");
        if (aaveAdapter != address(0)) {
            require(registry.getAdapter(registry.AAVE_LIKE()) == aaveAdapter, "Verify: aave adapter mismatch");
        }
        if (compoundAdapter != address(0)) {
            require(
                registry.getAdapter(registry.COMPOUND_LIKE()) == compoundAdapter, "Verify: compound adapter mismatch"
            );
        }
        if (morphoAdapter != address(0)) {
            require(registry.getAdapter(registry.MORPHO_LIKE()) == morphoAdapter, "Verify: morpho adapter mismatch");
        }

        // Writers/depositors
        require(rescueLog.isAuthorizedWriter(rescueExecutorAddr), "Verify: executor not log-writer");
        require(rescueLog.isAuthorizedWriter(ccipReceiverAddr), "Verify: receiver not log-writer");
        require(rescueLog.isAuthorizedWriter(rescueEscrowAddr), "Verify: escrow not log-writer");
        require(rescueEscrow.authorizedDepositors(rescueExecutorAddr), "Verify: executor not depositor");
        require(rescueEscrow.authorizedDepositors(ccipReceiverAddr), "Verify: receiver not depositor");

        // Optional workflow/reporter checks
        if (workflow != address(0)) {
            require(rescueExecutor.authorizedWorkflows(workflow), "Verify: workflow unauthorized");
        }
        if (healthMonitorAddr != address(0) && reporter != address(0)) {
            require(HealthMonitor(healthMonitorAddr).authorizedReporters(reporter), "Verify: reporter unauthorized");
        }

        // Optional CCIP lane checks
        if (ccipRouter != address(0)) {
            require(rescueExecutor.ccipRouter() == ccipRouter, "Verify: executor router mismatch");
            require(ccipReceiver.ccipRouter() == ccipRouter, "Verify: receiver router mismatch");
        }
        if (destSelector != 0) {
            require(rescueExecutor.trustedDestinationChains(destSelector), "Verify: dest selector not trusted");
            if (destReceiver != address(0)) {
                require(rescueExecutor.chainReceivers(destSelector) == destReceiver, "Verify: dest receiver mismatch");
            }
        }
        if (sourceSelector != 0) {
            require(ccipReceiver.isAllowedSourceChain(sourceSelector), "Verify: source selector not allowed");
            if (sourceSender != address(0)) {
                require(ccipReceiver.isAllowedSender(sourceSelector, sourceSender), "Verify: source sender not allowed");
            }
        }

        console.log("Reprieve stack verification passed on chain:", block.chainid);
    }
}
