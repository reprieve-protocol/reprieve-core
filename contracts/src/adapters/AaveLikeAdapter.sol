// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {BaseAdapter, IProtocolWithHF} from "./BaseAdapter.sol";
import {ILendingLikeProtocol} from "../interfaces/ILendingLikeProtocol.sol";

/**
 * @title AaveLikeAdapter
 * @notice Reprieve adapter for Aave V3-style lending protocols
 * @dev Uses Pool.supply/borrow/repay/withdraw interface
 */
contract AaveLikeAdapter is BaseAdapter {
    using SafeERC20 for IERC20;

    /// @notice Aave Pool referral code (0 for no referral)
    uint16 public constant REFERRAL_CODE = 0;

    constructor(
        address _protocol,
        address _collateralAsset,
        address _debtAsset,
        address _owner
    ) BaseAdapter(_protocol, _collateralAsset, _debtAsset, "AaveV3", _owner) {}

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
        return IProtocolWithHF(protocol).getHealthFactor(user);
    }

    function availableCollateral(address user, address asset) external view override returns (uint256) {
        if (asset != collateralAsset) revert UnsupportedAsset();
        
        IProtocolWithHF proto = IProtocolWithHF(protocol);
        ILendingLikeProtocol.Position memory pos = proto.getUserPosition(user);
        
        // Available = total collateral - locked (simplified: all is available if healthy)
        // In Aave, collateral is always withdrawable up to HF limit
        if (pos.debt == 0) {
            return pos.collateral;
        }
        
        // Rough estimate: can withdraw collateral while maintaining HF > 1.1
        // For demo: return 80% of excess collateral
        uint256 hf = proto.getHealthFactor(user);
        if (hf <= 1.1e18) {
            return 0; // Too risky to withdraw
        }
        
        // Simplified: can withdraw up to (HF - 1.1) / HF * collateral
        uint256 withdrawable = (pos.collateral * (hf - 1.1e18)) / hf;
        return withdrawable > pos.collateral ? 0 : withdrawable;
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
        
        // Get the aToken address from the pool
        (bool success, bytes memory data) = protocol.call(
            abi.encodeWithSignature("aToken()")
        );
        if (!success) revert WithdrawFailed();
        address aToken = abi.decode(data, (address));
        
        // Transfer aTokens from user to this adapter (requires user approval)
        IERC20(aToken).transferFrom(user, address(this), amount);
        
        // Call withdrawFor - pool will burn adapter's aTokens and withdraw on behalf of user
        (bool withdrawSuccess, ) = protocol.call(
            abi.encodeWithSignature(
                "withdrawFor(address,address,uint256,address)",
                user,
                asset,
                amount,
                to
            )
        );
        if (!withdrawSuccess) revert WithdrawFailed();
        
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
        
        // Aave interface: repay(asset, amount, interestRateMode, onBehalfOf)
        // Using variable rate mode (2) for Aave v3
        (bool success, ) = protocol.call(
            abi.encodeWithSignature(
                "repay(address,uint256,uint256,address)",
                asset,
                amount,
                uint256(2), // Variable interest rate mode
                user
            )
        );
        
        if (!success) revert RepayFailed();
        
        emit DebtRepaid(user, asset, amount);
    }
}
