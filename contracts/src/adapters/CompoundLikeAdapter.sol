// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {BaseAdapter, IProtocolWithHF} from "./BaseAdapter.sol";
import {ILendingLikeProtocol} from "../interfaces/ILendingLikeProtocol.sol";

/**
 * @title CompoundLikeAdapter
 * @notice Reprieve adapter for Compound V2-style lending protocols
 * @dev Uses cToken mint/redeem/borrow/repayBorrow interface
 * 
 * Compound-specific differences from Aave:
 * - Supply is called "mint" (cTokens minted)
 * - Withdraw is called "redeem" (cTokens burned)
 * - Repay has "repayBorrow" and "repayBorrowBehalf" variants
 */
contract CompoundLikeAdapter is BaseAdapter {
    using SafeERC20 for IERC20;

    /// @notice The cToken contract for collateral
    address public immutable cToken;

    constructor(
        address _protocol,
        address _collateralAsset,
        address _debtAsset,
        address _cToken,
        address _owner
    ) BaseAdapter(_protocol, _collateralAsset, _debtAsset, "CompoundV2", _owner) {
        if (_cToken == address(0)) revert ZeroAddress();
        cToken = _cToken;
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
        // Compound doesn't have HF directly, calculate from account liquidity
        // For demo, use the underlying protocol's HF calculation
        return _getProtocolHF(user);
    }

    function availableCollateral(address user, address asset) external view override returns (uint256) {
        if (asset != collateralAsset) revert UnsupportedAsset();
        
        // In Compound, available collateral = cToken balance converted to underlying
        // For simplicity, use the protocol's position data
        IProtocolWithHF proto = IProtocolWithHF(protocol);
        ILendingLikeProtocol.Position memory pos = proto.getUserPosition(user);
        
        // All collateral is withdrawable if no debt, otherwise limited by collateral factor
        if (pos.debt == 0) {
            return pos.collateral;
        }
        
        // Check account health - can withdraw if above threshold
        uint256 hf = _getProtocolHF(user);
        if (hf <= 1.05e18) {
            return 0;
        }
        
        // Can withdraw up to maintaining 1.05 HF
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
        
        // Compound: redeem cTokens for underlying
        // In our mock, this calls through to the underlying engine
        // The protocol must handle the cToken -> underlying conversion
        
        // For the mock CompoundMarket, we use withdraw interface
        // In real Compound, would use cToken.redeem()
        _redeemUnderlying(asset, amount, to);
        
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
        
        // Compound: repayBorrowBehalf
        // In our mock, we use repay on behalf
        _repayBorrowBehalf(user, asset, amount);
        
        emit DebtRepaid(user, asset, amount);
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
        return type(uint256).max; // No position = healthy
    }

    function _redeemUnderlying(address asset, uint256 amount, address to) internal {
        // Try Compound-style redeem first
        (bool success, ) = protocol.call(
            abi.encodeWithSignature("redeem(address,uint256)", asset, amount)
        );
        
        if (!success) {
            // Fallback to generic withdraw
            (bool success2, ) = protocol.call(
                abi.encodeWithSignature("withdraw(address,uint256,address)", asset, amount, to)
            );
            if (!success2) revert WithdrawFailed();
        }
        
        // If we redeemed to this contract, transfer to recipient
        uint256 balance = IERC20(asset).balanceOf(address(this));
        if (balance > 0) {
            IERC20(asset).safeTransfer(to, balance);
        }
    }

    function _repayBorrowBehalf(address user, address asset, uint256 amount) internal {
        // Try Compound-style repayBorrowBehalf
        (bool success, ) = protocol.call(
            abi.encodeWithSignature("repayBorrowBehalf(address,address,uint256)", user, asset, amount)
        );
        
        if (!success) {
            // Fallback to generic repay
            (bool success2, ) = protocol.call(
                abi.encodeWithSignature("repay(address,uint256,address)", asset, amount, user)
            );
            if (!success2) revert RepayFailed();
        }
    }
}
