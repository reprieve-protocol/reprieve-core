// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {BaseLendingEngine} from "./BaseLendingEngine.sol";
import {MockVaultShare} from "./MockVaultShare.sol";

/**
 * @notice Minimal Morpho Blue-style market mock for Reprieve demo
 * @dev Simplified: share-based accounting, supplyCollateral/borrow pattern
 */
contract MockMorphoMarket {
    using SafeERC20 for IERC20;

    address public immutable collateral;
    address public immutable loanToken;
    address public immutable oracle;
    BaseLendingEngine public immutable engine;
    MockVaultShare public immutable vaultShare;
    address public owner;

    // Cached risk params for easy access
    uint256 public immutable LTV_BPS;
    uint256 public immutable LIQUIDATION_THRESHOLD_BPS;

    struct MorphoPosition {
        uint256 supplyShares;
        uint128 collateral;
        uint128 borrowShares;
    }
    
    mapping(address => MorphoPosition) public position;
    uint256 public totalSupplyShares;
    uint256 public totalBorrowShares;
    uint256 public totalSupplyAssets;
    uint256 public totalBorrowAssets;

    event Supply(address indexed caller, address indexed onBehalfOf, uint256 assets, uint256 shares);
    event SupplyCollateral(address indexed caller, address indexed onBehalfOf, uint256 assets);
    event Borrow(address indexed caller, address indexed onBehalfOf, uint256 assets, uint256 shares);
    event Repay(address indexed caller, address indexed onBehalfOf, uint256 assets, uint256 shares);
    event Liquidate(address indexed caller, address indexed borrower, uint256 repaidAssets, uint256 seizedAssets);

    constructor(address _collateral, address _loanToken, address _oracle, address _owner) {
        collateral = _collateral;
        loanToken = _loanToken;
        oracle = _oracle;
        engine = new BaseLendingEngine(_collateral, _loanToken, _oracle, _owner);
        vaultShare = new MockVaultShare("mWETH", "mWETH", _loanToken, address(this));
        owner = _owner;
        
        // Cache risk params
        (LTV_BPS, LIQUIDATION_THRESHOLD_BPS,,) = engine.riskParams();
        
        // Max approve engine so it can pull from this pool
        IERC20(_collateral).approve(address(engine), type(uint256).max);
        IERC20(_loanToken).approve(address(engine), type(uint256).max);
    }

    function supply(uint256 assets, address onBehalfOf, bytes calldata) external {
        IERC20(loanToken).safeTransferFrom(msg.sender, address(this), assets);
        engine.supply(loanToken, assets, onBehalfOf);
        
        uint256 shares = previewDeposit(assets);
        position[onBehalfOf].supplyShares += shares;
        totalSupplyShares += shares;
        totalSupplyAssets += assets;
        
        _mintShares(onBehalfOf, shares);
        emit Supply(msg.sender, onBehalfOf, assets, shares);
    }

    function supplyCollateral(uint256 assets, address onBehalfOf, bytes calldata) external {
        IERC20(collateral).safeTransferFrom(msg.sender, address(this), assets);
        engine.supply(collateral, assets, onBehalfOf);
        position[onBehalfOf].collateral += uint128(assets);
        emit SupplyCollateral(msg.sender, onBehalfOf, assets);
    }

    function borrow(uint256 assets, address onBehalfOf, bytes calldata) external {
        engine.borrow(loanToken, assets, onBehalfOf);
        IERC20(loanToken).safeTransfer(msg.sender, assets);
        
        uint256 shares = previewBorrow(assets);
        position[onBehalfOf].borrowShares += uint128(shares);
        totalBorrowShares += shares;
        totalBorrowAssets += assets;
        
        emit Borrow(msg.sender, onBehalfOf, assets, shares);
    }

    function repay(uint256 assets, address onBehalfOf, bytes calldata) external {
        IERC20(loanToken).safeTransferFrom(msg.sender, address(this), assets);
        engine.repay(loanToken, assets, onBehalfOf);
        
        uint256 shares = previewWithdraw(assets);
        position[onBehalfOf].supplyShares -= shares;
        totalSupplyShares -= shares;
        totalSupplyAssets -= assets;
        
        _burnShares(onBehalfOf, shares);
        emit Repay(msg.sender, onBehalfOf, assets, shares);
    }

    function liquidate(address borrower, uint256 seizedAssets, bytes calldata) external {
        // Pull debt from liquidator to repay
        BaseLendingEngine.Position memory pos = engine.getUserPosition(borrower);
        uint256 debtToRepay = pos.debt;
        
        if (seizedAssets > 0) {
            // Partial liquidation: calculate proportional debt
            // This is simplified - in reality would calculate based on collateral value
            debtToRepay = seizedAssets * engine.getCurrentHealthFactor(borrower) / 1e18;
        }
        
        IERC20(loanToken).safeTransferFrom(msg.sender, address(this), debtToRepay);
        engine.liquidate(borrower);
        
        // Return seized collateral to liquidator
        uint256 seized = IERC20(collateral).balanceOf(address(this));
        IERC20(collateral).safeTransfer(msg.sender, seized);
        
        emit Liquidate(msg.sender, borrower, debtToRepay, seized);
    }

    // Internal share management (simplified)
    function _mintShares(address to, uint256 shares) internal {
        // In a real implementation, this would call vaultShare.mint
        // For now, shares are just tracked in position mapping
    }

    function _burnShares(address from, uint256 shares) internal {
        // In a real implementation, this would call vaultShare.burn
        // For now, shares are just tracked in position mapping
    }

    // ERC4626-like preview functions
    function previewDeposit(uint256 assets) public view returns (uint256) {
        if (totalSupplyShares == 0) return assets;
        return assets * totalSupplyShares / totalSupplyAssets;
    }

    function previewBorrow(uint256 assets) public view returns (uint256) {
        if (totalBorrowShares == 0) return assets;
        return assets * totalBorrowShares / totalBorrowAssets;
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        return assets * totalSupplyShares / totalSupplyAssets;
    }

    function getUserPosition(address user) external view returns (BaseLendingEngine.Position memory) {
        return engine.getUserPosition(user);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return engine.getCurrentHealthFactor(user);
    }

    function liquidationThresholdBps() external view returns (uint256) {
        return LIQUIDATION_THRESHOLD_BPS;
    }

    function ltvBps() external view returns (uint256) {
        return LTV_BPS;
    }

    function debt() external view returns (address) { return loanToken; }
    function collateralDecimals() external pure returns (uint8) { return 18; }
    function debtDecimals() external pure returns (uint8) { return 6; }
}
