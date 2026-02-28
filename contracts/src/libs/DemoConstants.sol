// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DemoConstants
 * @notice Shared constants for Reprieve demo lending protocol mimics
 * @dev All constants aligned with demo-lending-merged.md specification
 */
library DemoConstants {
    // ============ Math Precision ============
    uint256 public constant WAD = 1e18;              // 18 decimal precision
    uint256 public constant BPS_BASE = 10000;        // Basis points base (100%)
    
    // ============ Risk Parameters ============
    uint256 public constant MAX_LTV_BPS = 7500;              // 75% max LTV
    uint256 public constant LIQUIDATION_THRESHOLD_BPS = 8000; // 80% liquidation threshold
    uint256 public constant LIQUIDATION_BONUS_BPS = 500;      // 5% liquidation bonus
    
    // ============ Interest Rate ============
    uint256 public constant BORROW_APR_BPS = 500;    // 5% fixed APR
    uint256 public constant SECONDS_PER_YEAR = 365 days;
    
    // ============ Budget Guard (Reprieve-specific) ============
    uint256 public constant PER_RESCUE_CAP_ETH = 0.05 ether;  // 0.05 ETH per rescue
    uint256 public constant DAILY_CAP_ETH = 0.2 ether;        // 0.2 ETH daily cap
    
    // ============ Rescue Parameters ============
    uint256 public constant SOURCE_RESERVE_FACTOR_BPS = 2000; // Don't withdraw >80% of source (20% reserve)
    uint256 public constant RECOVERY_BUFFER_BPS = 11000;      // Target HF = threshold × 1.10
    uint256 public constant EMERGENCY_HF_THRESHOLD = 1.1e18;  // Force rescue if any HF < 1.10
    
    // ============ Health Factor Defaults ============
    uint256 public constant DEFAULT_HF_THRESHOLD = 1.3e18;    // Default rescue threshold (1.3)
    uint256 public constant HF_PRECISION = 1e18;              // Health factor precision
    
    // ============ Oracle ============
    uint256 public constant DEFAULT_STALENESS_THRESHOLD = 30 minutes;
    uint256 public constant ORACLE_UPDATE_CADENCE = 60 seconds; // Target update cadence
    
    // ============ Timeouts ============
    uint256 public constant STALE_DATA_TIMEOUT = 30 minutes;  // Skip rescue if data older than this
    uint256 public constant RAPID_DETERIORATION_PCT = 20;     // Emit urgent event if HF drops >20%
}
