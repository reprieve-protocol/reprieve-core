// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DemoConstants} from "../../src/libs/DemoConstants.sol";

/**
 * @title SetupTest
 * @notice Baseline tests for Slide 0: Engineering Setup & Guardrails
 * @dev Validates constants, folder structure, and compilation
 */
contract SetupTest is Test {
    
    // ============ Constants Invariant Tests ============
    
    function test_Constants_MaxLtv() public pure {
        assertEq(DemoConstants.MAX_LTV_BPS, 7500, "Max LTV should be 75%");
    }
    
    function test_Constants_LiquidationThreshold() public pure {
        assertEq(DemoConstants.LIQUIDATION_THRESHOLD_BPS, 8000, "Liquidation threshold should be 80%");
    }
    
    function test_Constants_LiquidationBonus() public pure {
        assertEq(DemoConstants.LIQUIDATION_BONUS_BPS, 500, "Liquidation bonus should be 5%");
    }
    
    function test_Constants_BorrowApr() public pure {
        assertEq(DemoConstants.BORROW_APR_BPS, 500, "Borrow APR should be 5%");
    }
    
    function test_Constants_WadPrecision() public pure {
        assertEq(DemoConstants.WAD, 1e18, "WAD should be 1e18");
    }
    
    function test_Constants_BpsBase() public pure {
        assertEq(DemoConstants.BPS_BASE, 10000, "BPS_BASE should be 10000");
    }
    
    function test_Constants_BudgetCaps() public pure {
        assertEq(DemoConstants.PER_RESCUE_CAP_ETH, 0.05 ether, "Per-rescue cap should be 0.05 ETH");
        assertEq(DemoConstants.DAILY_CAP_ETH, 0.2 ether, "Daily cap should be 0.2 ETH");
    }
    
    function test_Constants_RecoveryBuffer() public pure {
        assertEq(DemoConstants.RECOVERY_BUFFER_BPS, 11000, "Recovery buffer should be 110% (1.1x)");
    }
    
    function test_Constants_SourceReserve() public pure {
        assertEq(DemoConstants.SOURCE_RESERVE_FACTOR_BPS, 2000, "Source reserve should be 20%");
    }
    
    function test_Constants_DefaultHfThreshold() public pure {
        assertEq(DemoConstants.DEFAULT_HF_THRESHOLD, 1.3e18, "Default HF threshold should be 1.3");
    }
    
    function test_Constants_RiskParamRelationship() public pure {
        // Max LTV should always be less than liquidation threshold
        assertLt(
            DemoConstants.MAX_LTV_BPS, 
            DemoConstants.LIQUIDATION_THRESHOLD_BPS,
            "Max LTV must be less than liquidation threshold"
        );
    }
    
    function test_Constants_OracleStaleness() public pure {
        assertEq(
            DemoConstants.DEFAULT_STALENESS_THRESHOLD, 
            30 minutes, 
            "Default staleness threshold should be 30 minutes"
        );
    }
    
    function test_Constants_SecondsPerYear() public pure {
        assertEq(DemoConstants.SECONDS_PER_YEAR, 365 days, "Seconds per year should be 365 days");
    }
    
    // ============ Math Sanity Tests ============
    
    function test_Constants_HfPrecision() public pure {
        assertEq(DemoConstants.HF_PRECISION, 1e18, "HF precision should be 1e18");
        assertEq(DemoConstants.HF_PRECISION, DemoConstants.WAD, "HF precision should match WAD");
    }
    
    function test_Constants_EmergencyThreshold() public pure {
        assertEq(DemoConstants.EMERGENCY_HF_THRESHOLD, 1.1e18, "Emergency threshold should be 1.1");
        assertLt(
            DemoConstants.EMERGENCY_HF_THRESHOLD,
            DemoConstants.DEFAULT_HF_THRESHOLD,
            "Emergency threshold should be below default threshold"
        );
    }
}
