// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {MockAavePool} from "../../src/mocks/MockAavePool.sol";

/**
 * @title ApproveAaveReceiptToken
 * @notice One-time helper: approves user's Aave receipt token (aToken) to the Aave adapter.
 * @dev Needed because rescue withdrawals use adapter.withdrawForRescue -> aToken.transferFrom(user,...).
 */
contract ApproveAaveReceiptToken is Script {
    function run() external {
        uint256 fallbackPk = vm.envUint("PRIVATE_KEY");
        uint256 userPk = vm.envOr("USER_PRIVATE_KEY", fallbackPk);
        address user = vm.addr(userPk);

        address aavePoolAddr = vm.envAddress("AAVE_POOL");
        address aaveAdapterAddr = vm.envAddress("AAVE_ADAPTER");

        require(aavePoolAddr != address(0), "ApproveAaveReceiptToken: AAVE_POOL missing");
        require(aaveAdapterAddr != address(0), "ApproveAaveReceiptToken: AAVE_ADAPTER missing");

        address aToken = address(MockAavePool(aavePoolAddr).aToken());

        uint256 currentAllowance = IERC20(aToken).allowance(user, aaveAdapterAddr);

        console.log("Current aToken allowance for adapter:", currentAllowance);

        vm.startBroadcast(userPk);
        IERC20(aToken).approve(aaveAdapterAddr, type(uint256).max);
        vm.stopBroadcast();

        uint256 allowance = IERC20(aToken).allowance(user, aaveAdapterAddr);
        console.log("Aave receipt approval set.");
        console.log("Chain ID:", block.chainid);
        console.log("User:", user);
        console.log("Aave Pool:", aavePoolAddr);
        console.log("aToken:", aToken);
        console.log("Adapter:", aaveAdapterAddr);
        console.log("Allowance:", allowance);
    }
}

