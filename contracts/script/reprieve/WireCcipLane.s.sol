// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {RescueExecutor} from "../../src/reprieve/RescueExecutor.sol";
import {CCIPReceiver} from "../../src/reprieve/CCIPReceiver.sol";
import {CCIPClient} from "../../src/reprieve/libs/CCIPClient.sol";

/**
 * @title WireCcipLane
 * @notice Configures source and destination CCIP lane permissions.
 * @dev Set LANE_MODE=SOURCE or LANE_MODE=DESTINATION.
 */
contract WireCcipLane is Script {
    function run() external {
        string memory mode = vm.envOr("LANE_MODE", string("SOURCE"));
        if (_eq(mode, "SOURCE")) {
            _runSource();
            return;
        }
        if (_eq(mode, "DESTINATION")) {
            _runDestination();
            return;
        }
        revert("WireCcipLane: LANE_MODE must be SOURCE or DESTINATION");
    }

    function _runSource() internal {
        uint256 ownerPk = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(ownerPk);

        address sourceExecutorAddr = vm.envAddress("SOURCE_EXECUTOR");
        address sourceRouter = vm.envOr("SOURCE_ROUTER", vm.envOr("CCIP_ROUTER", address(0)));
        uint64 destSelector = uint64(vm.envUint("DEST_CHAIN_SELECTOR"));
        address destReceiver = vm.envAddress("DEST_RECEIVER");
        uint256 gasLimit = vm.envOr("CCIP_GAS_LIMIT", uint256(300_000));
        bool allowOutOfOrder = vm.envOr("CCIP_ALLOW_OUT_OF_ORDER", true);

        RescueExecutor sourceExecutor = RescueExecutor(payable(sourceExecutorAddr));

        console.log("Wiring SOURCE lane as owner:", owner);
        console.log("SourceExecutor:", sourceExecutorAddr);
        console.log("Router:", sourceRouter);
        console.log("Dest selector:", destSelector);
        console.log("Dest receiver:", destReceiver);

        vm.startBroadcast(ownerPk);
        if (sourceRouter != address(0)) {
            sourceExecutor.setCcipRouter(sourceRouter);
        }
        sourceExecutor.setTrustedDestinationChain(destSelector, true);
        sourceExecutor.setChainReceiver(destSelector, destReceiver);
        sourceExecutor.setCcipExtraArgs(destSelector, CCIPClient.buildExtraArgs(gasLimit, allowOutOfOrder));
        vm.stopBroadcast();

        console.log("SOURCE lane wired.");
    }

    function _runDestination() internal {
        uint256 ownerPk = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(ownerPk);

        address destReceiverAddr = vm.envAddress("DEST_RECEIVER");
        address destRouter = vm.envOr("DEST_ROUTER", vm.envOr("CCIP_ROUTER", address(0)));
        uint64 sourceSelector = uint64(vm.envUint("SOURCE_CHAIN_SELECTOR"));
        address sourceSender = vm.envAddress("SOURCE_SENDER");
        address destExecutorAddr = vm.envOr("DEST_EXECUTOR", address(0));

        CCIPReceiver destReceiver = CCIPReceiver(payable(destReceiverAddr));

        console.log("Wiring DESTINATION lane as owner:", owner);
        console.log("DestReceiver:", destReceiverAddr);
        console.log("Router:", destRouter);
        console.log("Source selector:", sourceSelector);
        console.log("Source sender:", sourceSender);

        vm.startBroadcast(ownerPk);
        if (destRouter != address(0)) {
            destReceiver.setRouter(destRouter);
            if (destExecutorAddr != address(0)) {
                RescueExecutor(payable(destExecutorAddr)).setCcipRouter(destRouter);
            }
        }
        destReceiver.setAllowedSourceChain(sourceSelector, true);
        destReceiver.setAllowedSender(sourceSelector, sourceSender, true);
        vm.stopBroadcast();

        console.log("DESTINATION lane wired.");
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
