// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockCCIPRouter} from "../../src/mocks/MockCCIPRouter.sol";
import {CCIPClient} from "../../src/reprieve/libs/CCIPClient.sol";

/**
 * @title DeployMockCCIPRouter
 * @notice One-shot deploy for mock programmable-token-transfer router.
 */
contract DeployMockCCIPRouter is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address linkToken = _resolveLinkToken();
        uint64 sourceChainSelector = uint64(vm.envOr("SOURCE_CHAIN_SELECTOR", _defaultSourceSelector()));
        uint256 baseSepoliaFee = vm.envOr("MOCK_FEE_BASE_SEPOLIA", uint256(0.01 ether));
        uint256 ethereumSepoliaFee = vm.envOr("MOCK_FEE_ETHEREUM_SEPOLIA", uint256(0.015 ether));

        console.log("Deploying MockCCIPRouter from:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("LINK token:", linkToken);
        console.log("Source selector:", sourceChainSelector);

        vm.startBroadcast(deployerPrivateKey);

        MockCCIPRouter router = new MockCCIPRouter(linkToken);
        router.setCurrentChainSelector(sourceChainSelector);
        router.setMockFee(CCIPClient.BASE_SEPOLIA, baseSepoliaFee);
        router.setMockFee(CCIPClient.ETHEREUM_SEPOLIA, ethereumSepoliaFee);

        vm.stopBroadcast();

        _writeArtifact(address(router), linkToken, sourceChainSelector, baseSepoliaFee, ethereumSepoliaFee);

        console.log("\n=== MockCCIPRouter Deployment ===");
        console.log("MockCCIPRouter:", address(router));
        console.log("Owner:", deployer);
    }

    function _resolveLinkToken() internal view returns (address linkToken) {
        linkToken = vm.envOr("LINK_TOKEN", address(0));
        if (linkToken != address(0)) return linkToken;

        if (block.chainid == 11155111) {
            linkToken = vm.envOr("ETHEREUM_SEPOLIA_LINK", address(0));
        } else if (block.chainid == 84532) {
            linkToken = vm.envOr("BASE_SEPOLIA_LINK", address(0));
        }

        require(linkToken != address(0), "DeployMockCCIPRouter: LINK token env required");
    }

    function _defaultSourceSelector() internal view returns (uint256) {
        if (block.chainid == 11155111) return CCIPClient.ETHEREUM_SEPOLIA;
        if (block.chainid == 84532) return CCIPClient.BASE_SEPOLIA;
        revert("DeployMockCCIPRouter: SOURCE_CHAIN_SELECTOR required on this chain");
    }

    function _writeArtifact(
        address router,
        address linkToken,
        uint64 sourceSelector,
        uint256 baseFee,
        uint256 ethFee
    ) internal {
        string memory path = string.concat("config/mock-ccip-router-", vm.toString(block.chainid), ".json");
        string memory out = string.concat(
            '{"chainId":',
            vm.toString(block.chainid),
            ',"contracts":{"MockCCIPRouter":"',
            vm.toString(router),
            '","LinkToken":"',
            vm.toString(linkToken),
            '"},"config":{"sourceChainSelector":',
            vm.toString(uint256(sourceSelector)),
            ',"fees":{"baseSepolia":"',
            vm.toString(baseFee),
            '","ethereumSepolia":"',
            vm.toString(ethFee),
            '"}}}'
        );

        vm.writeFile(path, out);
        console.log("Artifact written:", path);
    }
}
