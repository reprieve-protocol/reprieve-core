// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {BaseAdapter, IProtocolWithHF} from "./BaseAdapter.sol";
import {ILendingLikeProtocol} from "../interfaces/ILendingLikeProtocol.sol";

/**
 * @title MorphoLikeAdapter
 * @notice Reprieve adapter for Morpho Blue-style lending protocols
 * @dev Uses market-based supplyCollateral/borrow/repay/liquidate interface
 * 
 * Morpho-specific differences:
 * - Supply and supplyCollateral are separate (supply = earn interest, supplyCollateral = borrow against)
 * - Uses bytes data for extra params
 * - Shares-based accounting for supply positions
 */
contract MorphoLikeAdapter is BaseAdapter {
    using SafeERC20 for IERC20;

    /// @notice Market ID (morpho market identifier)
    bytes32 public immutable marketId;

    constructor(
        address _protocol,
        address _collateralAsset,
        address _debtAsset,
        bytes32 _marketId,
        address _owner
    ) BaseAdapter(_protocol, _collateralAsset, _debtAsset, "MorphoBlue", _owner) {
        marketId = _marketId;
    }

    // ============ Position Discovery ============

    function discoverPositions(address user) external view override returns (Position[] memory) {
        Position[] memory positions = new Position[](1);
        positions[0] = _getPosition(user);
        
        // Only return if user has collateral or debt
        if (positions[0].collateralAmount == 0 && positions[0].debtAmount == 0) {
            return new Position[](0);
        }
        
        return positions;
    }

    function healthFactor(address user) external view override returns (uint256 hfWad) {
        return _getProtocolHF(user);
    }

    function availableCollateral(address user, address asset) external view override returns (uint256) {
        if (asset != collateralAsset) revert UnsupportedAsset();
        
        IProtocolWithHF proto = IProtocolWithHF(protocol);
        ILendingLikeProtocol.Position memory pos = proto.getUserPosition(user);
        
        // In Morpho, available collateral depends on LLTV (liquidation loan-to-value)
        // All supplied collateral is available if no debt
        if (pos.debt == 0) {
            return pos.collateral;
        }
        
        // Check health - can withdraw if HF above buffer
        uint256 hf = _getProtocolHF(user);
        if (hf <= 1.05e18) {
            return 0;
        }
        
        // Withdrawable while maintaining 1.05 HF
        uint256 withdrawable = (pos.collateral * (hf - 1.05e18)) / hf;
        return withdrawable;
    }

    function getDebt(address user, address asset) external view override returns (uint256) {
        if (asset != debtAsset) revert UnsupportedAsset();
        IProtocolWithHF proto = IProtocolWithHF(protocol);
        ILendingLikeProtocol.Position memory pos = proto.getUserPosition(user);
        return pos.debt;
    }

    // ============ Rescue Actions ============

    function withdrawForRescue(address user, address asset, uint256 amount, address to) 
        external 
        override 
        whenNotPaused 
    {
        if (amount == 0) revert ZeroAmount();
        if (asset != collateralAsset) revert UnsupportedAsset();
        if (to == address(0)) revert ZeroAddress();
        
        // Morpho: withdraw collateral
        // Morpho uses supplyCollateral/withdrawCollateral pattern
        _withdrawCollateral(amount, to);
        
        emit CollateralWithdrawn(user, asset, amount, to);
    }

    function repayForRescue(address user, address asset, uint256 amount) 
        external 
        override 
        whenNotPaused 
    {
        if (amount == 0) revert ZeroAmount();
        if (asset != debtAsset) revert UnsupportedAsset();
        
        // Pull debt tokens from caller (Reprieve)
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        
        // Approve protocol to spend
        IERC20(asset).approve(protocol, amount);
        
        // Morpho: repay shares
        // In our mock, we use repay with bytes data
        _repayMorpho(user, asset, amount);
        
        emit DebtRepaid(user, asset, amount);
    }

    function supplyForRescue(address user, address asset, uint256 amount)
        external
        override
        whenNotPaused
    {
        if (amount == 0) revert ZeroAmount();
        if (asset != collateralAsset) revert UnsupportedAsset();

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(asset).approve(protocol, amount);

        _supplyCollateralFor(user, amount);

        emit CollateralSupplied(user, asset, amount);
    }

    // ============ Internal Functions ============

    function _getProtocolHF(address user) internal view returns (uint256) {
        // Call the protocol's HF function
        (bool success, bytes memory data) = protocol.staticcall(
            abi.encodeWithSignature("getHealthFactor(address)", user)
        );
        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        return type(uint256).max;
    }

    function _withdrawCollateral(uint256 amount, address to) internal {
        // Try Morpho-style withdraw (supplyCollateral with negative logic)
        // Actually, Morpho has a separate withdrawCollateral function
        (bool success, ) = protocol.call(
            abi.encodeWithSignature(
                "withdrawCollateral(uint256,address,bytes)",
                amount,
                to,
                ""
            )
        );
        
        if (!success) {
            // Fallback: try generic withdraw
            (bool success2, ) = protocol.call(
                abi.encodeWithSignature(
                    "withdraw(address,uint256,address)",
                    collateralAsset,
                    amount,
                    to
                )
            );
            if (!success2) revert WithdrawFailed();
        }
    }

    function _repayMorpho(address user, address asset, uint256 amount) internal {
        // Try Morpho-style repay
        (bool success, ) = protocol.call(
            abi.encodeWithSignature(
                "repay(uint256,address,bytes)",
                amount,
                user,
                ""
            )
        );
        
        if (!success) {
            // Fallback to generic repay
            (bool success2, ) = protocol.call(
                abi.encodeWithSignature("repay(address,uint256,address)", asset, amount, user)
            );
            if (!success2) revert RepayFailed();
        }
    }

    function _supplyCollateralFor(address user, uint256 amount) internal {
        (bool success, ) = protocol.call(
            abi.encodeWithSignature(
                "supplyCollateral(uint256,address,bytes)",
                amount,
                user,
                ""
            )
        );
        if (!success) {
            (bool success2, ) = protocol.call(
                abi.encodeWithSignature("supply(address,uint256,address)", collateralAsset, amount, user)
            );
            if (!success2) revert RepayFailed();
        }
    }
}
