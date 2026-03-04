// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockAavePool} from "../../src/mocks/MockAavePool.sol";
import {RescueExecutor} from "../../src/reprieve/RescueExecutor.sol";
import {ReprieveTypes} from "../../src/reprieve/libs/ReprieveTypes.sol";

/**
 * @title CrossChainRescueSetupSource
 * @notice Phase 1: Prepare source-chain position and balances for cross-chain rescue.
 */
contract CrossChainRescueSetupSource is Script {
    function run() external {
        uint256 ownerPk = vm.envUint("PRIVATE_KEY");
        uint256 workflowPk = vm.envOr("WORKFLOW_PRIVATE_KEY", ownerPk);
        uint256 userPk = vm.envOr("USER_PRIVATE_KEY", ownerPk);
        uint256 minterPk = vm.envOr("MINTER_PRIVATE_KEY", ownerPk);

        address owner = vm.addr(ownerPk);
        address workflow = vm.addr(workflowPk);
        address user = vm.addr(userPk);

        address sourceExecutorAddr = vm.envAddress("SOURCE_EXECUTOR");
        address sourceAavePoolAddr = vm.envAddress("SOURCE_AAVE_POOL");
        address sourceAaveAdapter = vm.envAddress("SOURCE_AAVE_ADAPTER");
        address collateralAsset = vm.envAddress("COLLATERAL_ASSET");
        address debtAsset = vm.envAddress("DEBT_ASSET");
        string memory rescueModeRaw = vm.envOr("RESCUE_MODE", string("TOP_UP"));
        ReprieveTypes.RescueMode rescueMode = _parseMode(rescueModeRaw);

        uint256 userCollateralMint = vm.envOr("USER_COLLATERAL_MINT", uint256(20 ether));
        uint256 sourceSupply = vm.envOr("SOURCE_SUPPLY_COLLATERAL", uint256(10 ether));

        MockERC20 collateral = MockERC20(collateralAsset);
        MockAavePool sourceAavePool = MockAavePool(sourceAavePoolAddr);
        RescueExecutor sourceExecutor = RescueExecutor(payable(sourceExecutorAddr));

        console.log("Cross-chain rescue setup source on chain:", block.chainid);
        console.log("Owner:", owner);
        console.log("Workflow:", workflow);
        console.log("User:", user);
        console.log("Mode:", rescueMode == ReprieveTypes.RescueMode.TOP_UP ? "TOP_UP" : "REPAY");

        vm.startBroadcast(ownerPk);
        sourceExecutor.setAuthorizedWorkflow(workflow, true);
        sourceAavePool.engine().setAuthorizedOperator(sourceAavePoolAddr, true);
        vm.stopBroadcast();

        vm.startBroadcast(minterPk);
        collateral.mint(user, userCollateralMint);
        vm.stopBroadcast();

        vm.startBroadcast(userPk);
        collateral.approve(sourceAavePoolAddr, type(uint256).max);
        sourceAavePool.supply(collateralAsset, sourceSupply, user, 0);
        sourceAavePool.aToken().approve(sourceAaveAdapter, type(uint256).max);
        vm.stopBroadcast();

        _writeArtifact(sourceExecutorAddr, sourceAavePoolAddr, sourceAaveAdapter, collateralAsset, debtAsset, rescueModeRaw);
        console.log("Source setup complete.");
    }

    function _writeArtifact(
        address sourceExecutorAddr,
        address sourceAavePoolAddr,
        address sourceAaveAdapter,
        address collateralAsset,
        address debtAsset,
        string memory rescueModeRaw
    ) internal {
        string memory path = string.concat("config/cross-chain-rescue-source-", vm.toString(block.chainid), ".json");
        string memory out = string.concat(
            '{"chainId":',
            vm.toString(block.chainid),
            ',"mode":"',
            rescueModeRaw,
            '","source":{"executor":"',
            vm.toString(sourceExecutorAddr),
            '","aavePool":"',
            vm.toString(sourceAavePoolAddr),
            '","aaveAdapter":"',
            vm.toString(sourceAaveAdapter),
            '","collateralAsset":"',
            vm.toString(collateralAsset),
            '","debtAsset":"',
            vm.toString(debtAsset),
            '"}}'
        );
        vm.writeFile(path, out);
        console.log("Artifact written:", path);
    }

    function _parseMode(string memory raw) internal pure returns (ReprieveTypes.RescueMode) {
        bytes32 modeHash = keccak256(bytes(raw));
        if (modeHash == keccak256(bytes("TOP_UP"))) {
            return ReprieveTypes.RescueMode.TOP_UP;
        }
        if (modeHash == keccak256(bytes("REPAY"))) {
            return ReprieveTypes.RescueMode.REPAY;
        }
        revert("CrossChainRescueSetupSource: RESCUE_MODE must be TOP_UP or REPAY");
    }
}
