// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockAavePool} from "../../src/mocks/MockAavePool.sol";
import {MockCompoundMarket} from "../../src/mocks/MockCompoundMarket.sol";
import {MockMorphoMarket} from "../../src/mocks/MockMorphoMarket.sol";
import {BaseLendingEngine} from "../../src/mocks/BaseLendingEngine.sol";

/**
 * @title SetRiskParams
 * @notice Applies risk parameter config to all three demo lending engines.
 * @dev Owner-only calls to each engine's setRiskParams.
 */
contract SetRiskParams is Script {
    function run() external {
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(ownerPrivateKey);

        string memory configPath = _configPath();
        string memory json = vm.readFile(configPath);

        address aavePoolAddr = _envOrConfigAddress("AAVE_POOL", json, ".contracts.MockAavePool");
        address compoundAddr = _envOrConfigAddress("COMPOUND_MARKET", json, ".contracts.MockCompoundComet");
        address morphoAddr = _envOrConfigAddress("MORPHO_MARKET", json, ".contracts.MockMorphoMarket");

        require(aavePoolAddr != address(0), "SetRiskParams: missing AAVE_POOL");
        require(compoundAddr != address(0), "SetRiskParams: missing COMPOUND_MARKET");
        require(morphoAddr != address(0), "SetRiskParams: missing MORPHO_MARKET");

        uint256 maxLtvBps = vm.envOr("MAX_LTV_BPS", vm.parseJsonUint(json, ".riskParams.maxLtvBps"));
        uint256 liquidationThresholdBps =
            vm.envOr("LIQ_THRESHOLD_BPS", vm.parseJsonUint(json, ".riskParams.liquidationThresholdBps"));
        uint256 liquidationBonusBps =
            vm.envOr("LIQ_BONUS_BPS", vm.parseJsonUint(json, ".riskParams.liquidationBonusBps"));
        uint256 borrowAprBps = vm.envOr("BORROW_APR_BPS", vm.parseJsonUint(json, ".riskParams.borrowAprBps"));

        console.log("Applying risk params from owner:", owner);
        console.log("Chain ID:", block.chainid);
        console.log("maxLtvBps:", maxLtvBps);
        console.log("liquidationThresholdBps:", liquidationThresholdBps);
        console.log("liquidationBonusBps:", liquidationBonusBps);
        console.log("borrowAprBps:", borrowAprBps);

        vm.startBroadcast(ownerPrivateKey);

        _apply(MockAavePool(aavePoolAddr).engine(), maxLtvBps, liquidationThresholdBps, liquidationBonusBps, borrowAprBps);
        _apply(
            MockCompoundMarket(compoundAddr).engine(), maxLtvBps, liquidationThresholdBps, liquidationBonusBps, borrowAprBps
        );
        _apply(MockMorphoMarket(morphoAddr).engine(), maxLtvBps, liquidationThresholdBps, liquidationBonusBps, borrowAprBps);

        vm.stopBroadcast();

        console.log("Risk params updated on all demo protocol engines.");
    }

    function _apply(
        BaseLendingEngine engine,
        uint256 maxLtvBps,
        uint256 liquidationThresholdBps,
        uint256 liquidationBonusBps,
        uint256 borrowAprBps
    ) internal {
        engine.setRiskParams(maxLtvBps, liquidationThresholdBps, liquidationBonusBps, borrowAprBps);
        (uint256 cfgMaxLtv, uint256 cfgThreshold, uint256 cfgBonus, uint256 cfgApr) = engine.riskParams();
        require(cfgMaxLtv == maxLtvBps, "SetRiskParams: maxLtv mismatch");
        require(cfgThreshold == liquidationThresholdBps, "SetRiskParams: threshold mismatch");
        require(cfgBonus == liquidationBonusBps, "SetRiskParams: bonus mismatch");
        require(cfgApr == borrowAprBps, "SetRiskParams: apr mismatch");
    }

    function _configPath() internal view returns (string memory) {
        string memory path = vm.envOr("CONFIG_PATH", string(""));
        if (bytes(path).length > 0) return path;
        if (block.chainid == 11155111) return "config/ethereum-sepolia.json";
        if (block.chainid == 84532) return "config/base-sepolia.json";
        revert("SetRiskParams: CONFIG_PATH required for this chain");
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
}
