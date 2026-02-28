// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DemoConstants} from "./DemoConstants.sol";

/**
 * @title LendingMath
 * @notice Math utilities for lending engine calculations
 * @dev All calculations use WAD precision (18 decimals)
 */
library LendingMath {
    
    /**
     * @notice Calculate interest accrued over time
     * @param principal Principal amount
     * @param aprBps Annual percentage rate in basis points
     * @param elapsedTime Time elapsed in seconds
     * @return interest Accrued interest amount
     */
    function calculateInterest(
        uint256 principal,
        uint256 aprBps,
        uint256 elapsedTime
    ) internal pure returns (uint256 interest) {
        // Interest = Principal * APR * Time / (10000 * SecondsPerYear)
        // Using WAD precision: (principal * aprBps * elapsedTime * WAD) / (BPS_BASE * SECONDS_PER_YEAR * WAD)
        // Simplified: (principal * aprBps * elapsedTime) / (BPS_BASE * SECONDS_PER_YEAR)
        return (principal * aprBps * elapsedTime) / (DemoConstants.BPS_BASE * DemoConstants.SECONDS_PER_YEAR);
    }
    
    /**
     * @notice Calculate collateral value in USD
     * @param collateralAmount Collateral token amount
     * @param collateralPrice Price of collateral in USD (WAD precision)
     * @param collateralDecimals Collateral token decimals
     * @return valueUSD Collateral value in USD (WAD precision)
     */
    function collateralValueUSD(
        uint256 collateralAmount,
        uint256 collateralPrice,
        uint8 collateralDecimals
    ) internal pure returns (uint256 valueUSD) {
        // value = amount * price / 10^decimals
        // Convert to WAD: (amount * price * WAD) / 10^decimals / WAD = (amount * price) / 10^decimals
        return (collateralAmount * collateralPrice) / (10 ** collateralDecimals);
    }
    
    /**
     * @notice Calculate debt value in USD
     * @param _debtAmount Debt token amount
     * @param _debtPrice Price of debt token in USD (WAD precision)
     * @param _debtDecimals Debt token decimals
     * @return valueUSD Debt value in USD (WAD precision)
     */
    function debtValueUSD(
        uint256 _debtAmount,
        uint256 _debtPrice,
        uint8 _debtDecimals
    ) internal pure returns (uint256 valueUSD) {
        return (_debtAmount * _debtPrice) / (10 ** _debtDecimals);
    }
    
    /**
     * @notice Calculate maximum borrow amount based on collateral
     * @param _collateralValueUSD Collateral value in USD (WAD precision)
     * @param _maxLtvBps Maximum LTV in basis points
     * @return maxBorrowUSD Maximum borrow amount in USD (WAD precision)
     */
    function calculateMaxBorrow(
        uint256 _collateralValueUSD,
        uint256 _maxLtvBps
    ) internal pure returns (uint256 maxBorrowUSD) {
        return (_collateralValueUSD * _maxLtvBps) / DemoConstants.BPS_BASE;
    }
    
    /**
     * @notice Calculate health factor
     * @param _collateralValueUSD Collateral value in USD (WAD precision)
     * @param _debtValueUSD Debt value in USD (WAD precision)
     * @param _liquidationThresholdBps Liquidation threshold in basis points
     * @return hfWad Health factor in WAD precision (1e18 = 1.0)
     */
    function calculateHealthFactor(
        uint256 _collateralValueUSD,
        uint256 _debtValueUSD,
        uint256 _liquidationThresholdBps
    ) internal pure returns (uint256 hfWad) {
        if (_debtValueUSD == 0) {
            return type(uint256).max; // No debt = infinite health
        }
        
        // HF = (Collateral Value * Liquidation Threshold) / Debt Value
        // In WAD: (collateralValue * ltBps * WAD) / (BPS_BASE * debtValue)
        return (_collateralValueUSD * _liquidationThresholdBps * DemoConstants.WAD) / 
               (DemoConstants.BPS_BASE * _debtValueUSD);
    }
    
    /**
     * @notice Calculate liquidation bonus
     * @param debtValueUSD Debt value being repaid (WAD precision)
     * @param liquidationBonusBps Liquidation bonus in basis points
     * @return bonusUSD Bonus amount in USD (WAD precision)
     */
    function liquidationBonus(
        uint256 debtValueUSD,
        uint256 liquidationBonusBps
    ) internal pure returns (uint256 bonusUSD) {
        return (debtValueUSD * liquidationBonusBps) / DemoConstants.BPS_BASE;
    }
    
    /**
     * @notice Calculate LTV ratio
     * @param _debtValueUSD Debt value in USD (WAD precision)
     * @param _collateralValueUSD Collateral value in USD (WAD precision)
     * @return ltvBps LTV in basis points
     */
    function calculateLTV(
        uint256 _debtValueUSD,
        uint256 _collateralValueUSD
    ) internal pure returns (uint256 ltvBps) {
        if (_collateralValueUSD == 0) {
            return 0;
        }
        return (_debtValueUSD * DemoConstants.BPS_BASE) / _collateralValueUSD;
    }
    
    /**
     * @notice Check if position is eligible for liquidation
     * @param hfWad Health factor in WAD precision
     * @return isEligible True if HF < 1.0 (WAD)
     */
    function isLiquidatable(uint256 hfWad) internal pure returns (bool isEligible) {
        return hfWad < DemoConstants.WAD;
    }
    
    /**
     * @notice Calculate maximum withdrawable collateral
     * @param _collateralValueUSD Current collateral value (WAD precision)
     * @param _debtValueUSD Current debt value (WAD precision)
     * @param _maxLtvBps Maximum LTV in basis points
     * @return maxWithdrawUSD Maximum withdrawable value (WAD precision)
     */
    function calculateMaxWithdraw(
        uint256 _collateralValueUSD,
        uint256 _debtValueUSD,
        uint256 _maxLtvBps
    ) internal pure returns (uint256 maxWithdrawUSD) {
        if (_debtValueUSD == 0) {
            return _collateralValueUSD; // No debt = can withdraw all
        }
        
        // Max collateral value to maintain LTV: debt / maxLtv
        uint256 minRequiredCollateralValueUSD = (_debtValueUSD * DemoConstants.BPS_BASE) / _maxLtvBps;
        
        if (_collateralValueUSD <= minRequiredCollateralValueUSD) {
            return 0;
        }
        
        return _collateralValueUSD - minRequiredCollateralValueUSD;
    }
    
    /**
     * @notice Convert USD value to token amount
     * @param valueUSD Value in USD (WAD precision)
     * @param price Price of token in USD (WAD precision)
     * @param tokenDecimals Token decimals
     * @return amount Token amount
     */
    function usdToTokenAmount(
        uint256 valueUSD,
        uint256 price,
        uint8 tokenDecimals
    ) internal pure returns (uint256 amount) {
        // amount = valueUSD / price * 10^decimals
        // (valueUSD * 10^decimals) / price
        return (valueUSD * (10 ** tokenDecimals)) / price;
    }
    
    /**
     * @notice Calculate target debt for a given collateral value at max LTV
     * @param _collateralValueUSD Collateral value (WAD precision)
     * @param _maxLtvBps Maximum LTV in basis points
     * @return targetDebtUSD Target debt value (WAD precision)
     */
    function calculateTargetDebt(
        uint256 _collateralValueUSD,
        uint256 _maxLtvBps
    ) internal pure returns (uint256 targetDebtUSD) {
        return (_collateralValueUSD * _maxLtvBps) / DemoConstants.BPS_BASE;
    }
}
