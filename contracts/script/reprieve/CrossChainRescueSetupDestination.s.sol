// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockCompoundMarket} from "../../src/mocks/MockCompoundMarket.sol";
import {CompoundLikeAdapter} from "../../src/adapters/CompoundLikeAdapter.sol";
import {ReprieveTypes} from "../../src/reprieve/libs/ReprieveTypes.sol";

/**
 * @title CrossChainRescueSetupDestination
 * @notice Phase 2: Prepare destination-chain target position for cross-chain rescue.
 * @dev TOP_UP uses existing destination market; REPAY deploys opposite (hedging) destination market.
 */
contract CrossChainRescueSetupDestination is Script {
    function run() external {
        uint256 ownerPk = vm.envUint("PRIVATE_KEY");
        uint256 userPk = vm.envOr("USER_PRIVATE_KEY", ownerPk);
        uint256 minterPk = vm.envOr("MINTER_PRIVATE_KEY", ownerPk);

        address owner = vm.addr(ownerPk);
        address user = vm.addr(userPk);

        address compoundMarketAddr = vm.envAddress("COMPOUND_MARKET");
        address compoundAdapterAddr = vm.envAddress("COMPOUND_ADAPTER");
        address collateralAsset = vm.envAddress("COLLATERAL_ASSET");
        address debtAsset = vm.envAddress("DEBT_ASSET");
        string memory rescueModeRaw = vm.envOr("RESCUE_MODE", string("TOP_UP"));
        ReprieveTypes.RescueMode rescueMode = _parseMode(rescueModeRaw);

        uint256 topUpUserCollateralMint = vm.envOr("TARGET_USER_COLLATERAL_MINT", uint256(10 ether));
        uint256 topUpSupplyCollateral = vm.envOr("TARGET_SUPPLY_COLLATERAL", uint256(8 ether));
        uint256 topUpBorrowDebt = vm.envOr("TARGET_BORROW_DEBT", uint256(5_000e6));
        uint256 topUpEngineDebtLiquidity = vm.envOr("TARGET_ENGINE_DEBT_LIQUIDITY", uint256(100_000e6));

        uint256 repayUserDebtCollateralMint = vm.envOr("TARGET_REPAY_USER_COLLATERAL_MINT", uint256(20_000e6));
        uint256 repaySupplyDebtCollateral = vm.envOr("TARGET_REPAY_SUPPLY_COLLATERAL", uint256(10_000e6));
        uint256 repayBorrowOppositeDebt = vm.envOr("TARGET_REPAY_BORROW_DEBT", uint256(5 ether));
        uint256 repayEngineBorrowLiquidity = vm.envOr("TARGET_REPAY_ENGINE_BORROW_LIQUIDITY", uint256(1_000 ether));

        MockERC20 collateral = MockERC20(collateralAsset);
        MockERC20 debt = MockERC20(debtAsset);
        MockCompoundMarket baseCompoundMarket = MockCompoundMarket(compoundMarketAddr);

        address targetAdapter = compoundAdapterAddr;
        address targetMarket = compoundMarketAddr;
        address rescueDebtAsset = debtAsset;
        address rescueCollateralAsset = collateralAsset;

        console.log("Cross-chain rescue setup destination on chain:", block.chainid);
        console.log("Owner:", owner);
        console.log("User:", user);
        console.log("Mode:", rescueMode == ReprieveTypes.RescueMode.TOP_UP ? "TOP_UP" : "REPAY");

        if (rescueMode == ReprieveTypes.RescueMode.TOP_UP) {
            vm.startBroadcast(ownerPk);
            baseCompoundMarket.engine().setAuthorizedOperator(compoundMarketAddr, true);
            vm.stopBroadcast();

            vm.startBroadcast(minterPk);
            collateral.mint(user, topUpUserCollateralMint);
            debt.mint(address(baseCompoundMarket.engine()), topUpEngineDebtLiquidity);
            vm.stopBroadcast();

            vm.startBroadcast(userPk);
            collateral.approve(compoundMarketAddr, type(uint256).max);
            baseCompoundMarket.mint(collateralAsset, topUpSupplyCollateral);
            baseCompoundMarket.borrow(debtAsset, topUpBorrowDebt);
            vm.stopBroadcast();
        } else {
            vm.startBroadcast(ownerPk);
            MockCompoundMarket repayTargetMarket =
                new MockCompoundMarket(debtAsset, collateralAsset, baseCompoundMarket.oracle(), owner);
            CompoundLikeAdapter repayTargetAdapter = new CompoundLikeAdapter(
                address(repayTargetMarket),
                debtAsset,
                collateralAsset,
                address(repayTargetMarket.cToken()),
                owner
            );
            repayTargetMarket.engine().setAuthorizedOperator(address(repayTargetMarket), true);
            vm.stopBroadcast();

            vm.startBroadcast(minterPk);
            debt.mint(user, repayUserDebtCollateralMint);
            collateral.mint(address(repayTargetMarket.engine()), repayEngineBorrowLiquidity);
            vm.stopBroadcast();

            vm.startBroadcast(userPk);
            debt.approve(address(repayTargetMarket), type(uint256).max);
            repayTargetMarket.mint(debtAsset, repaySupplyDebtCollateral);
            repayTargetMarket.borrow(collateralAsset, repayBorrowOppositeDebt);
            vm.stopBroadcast();

            targetAdapter = address(repayTargetAdapter);
            targetMarket = address(repayTargetMarket);
            rescueDebtAsset = collateralAsset;
            rescueCollateralAsset = debtAsset;

            console.log("Opposite repay target market:", targetMarket);
            console.log("Opposite repay target adapter:", targetAdapter);
        }

        _writeArtifact(targetAdapter, targetMarket, rescueDebtAsset, rescueCollateralAsset, rescueModeRaw);
        console.log("Destination setup complete.");
    }

    function _writeArtifact(
        address targetAdapter,
        address targetMarket,
        address rescueDebtAsset,
        address rescueCollateralAsset,
        string memory rescueModeRaw
    ) internal {
        string memory path = string.concat("config/cross-chain-rescue-destination-", vm.toString(block.chainid), ".json");
        string memory out = string.concat(
            '{"chainId":',
            vm.toString(block.chainid),
            ',"mode":"',
            rescueModeRaw,
            '","target":{"targetAdapter":"',
            vm.toString(targetAdapter),
            '","targetMarket":"',
            vm.toString(targetMarket),
            '","rescueDebtAsset":"',
            vm.toString(rescueDebtAsset),
            '","rescueCollateralAsset":"',
            vm.toString(rescueCollateralAsset),
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
        revert("CrossChainRescueSetupDestination: RESCUE_MODE must be TOP_UP or REPAY");
    }
}

