# Slide 0: Engineering Setup & Guardrails - Proof of Work

## Date: 2026-02-28

## Actions Completed

### 1. Folder Structure Created
```
contracts/
├── src/
│   ├── mocks/          # For protocol mimic contracts (Slide 3)
│   ├── adapters/       # For Reprieve adapter contracts (Slide 4)
│   ├── interfaces/     # Shared interfaces
│   ├── libs/           # Libraries (constants, math)
│   └── ...
├── script/demo/        # Deployment and utility scripts
├── test/demo/          # Test files
└── config/             # Chain-specific config files
```

### 2. Shared Interfaces Defined

#### `ILendingLikeProtocol.sol`
- Common interface for all lending protocol mimics
- Position struct: collateral, debt, ltvBps, liquidationThresholdBps
- Methods: getUserPosition, getHealthFactor, supply, withdraw, borrow, repay, liquidate
- Events: Supplied, Withdrawn, Borrowed, Repaid, PositionUpdated, Liquidated

#### `IDemoOracle.sol`
- Centralized oracle with owner-only price updates
- Staleness tracking with configurable threshold
- Methods: getPrice, getLatestPrice, setPrice, isStale
- Events: PriceUpdated, StalenessThresholdUpdated

#### `IReprieveAdapter.sol`
- Adapter interface for Reprieve protocol integration
- Position struct with full position metadata
- Methods: discoverPositions, healthFactor, availableCollateral, withdrawForRescue, repayForRescue
- Events: PositionDiscovered, CollateralWithdrawn, DebtRepaid

### 3. Shared Constants Library (`DemoConstants.sol`)

| Constant | Value | Description |
|----------|-------|-------------|
| WAD | 1e18 | 18-decimal precision |
| MAX_LTV_BPS | 7500 | 75% max LTV |
| LIQUIDATION_THRESHOLD_BPS | 8000 | 80% liquidation threshold |
| LIQUIDATION_BONUS_BPS | 500 | 5% liquidation bonus |
| BORROW_APR_BPS | 500 | 5% fixed APR |
| PER_RESCUE_CAP_ETH | 0.05 ether | 0.05 ETH per rescue cap |
| DAILY_CAP_ETH | 0.2 ether | 0.2 ETH daily cap |
| SOURCE_RESERVE_FACTOR_BPS | 2000 | Never withdraw >80% of source |
| RECOVERY_BUFFER_BPS | 11000 | Target HF = threshold × 1.10 |
| DEFAULT_HF_THRESHOLD | 1.3e18 | Default rescue threshold |
| EMERGENCY_HF_THRESHOLD | 1.1e18 | Force rescue HF |
| DEFAULT_STALENESS_THRESHOLD | 30 minutes | Oracle staleness threshold |
| STALE_DATA_TIMEOUT | 30 minutes | Skip rescue if data older than this |

### 4. Config Files Created

#### `config/ethereum-sepolia.json`
- Chain ID: 11155111
- Risk params: 75% LTV, 80% LT, 5% APR, 5% liquidation bonus
- Token params: WETH collateral (18 decimals), USDC debt (6 decimals)
- Initial WETH price: $2000 (WAD precision)

#### `config/base-sepolia.json`
- Chain ID: 84532
- Same risk params as Ethereum Sepolia

### 5. Test Suite (`test/demo/Setup.t.sol`)

15 invariant tests covering:
- All risk parameter constants
- Budget cap constants
- Recovery buffer and source reserve
- Health factor thresholds
- Math precision (WAD/BPS)
- Oracle staleness settings
- Risk parameter relationships (e.g., LTV < liquidation threshold)

All tests pass:
```
Ran 15 tests for test/demo/Setup.t.sol:SetupTest
[PASS] test_Constants_BorrowApr() (gas: 351)
[PASS] test_Constants_BpsBase() (gas: 329)
[PASS] test_Constants_BudgetCaps() (gas: 454)
[PASS] test_Constants_DefaultHfThreshold() (gas: 337)
[PASS] test_Constants_EmergencyThreshold() (gas: 441)
[PASS] test_Constants_HfPrecision() (gas: 487)
[PASS] test_Constants_LiquidationBonus() (gas: 307)
[PASS] test_Constants_LiquidationThreshold() (gas: 348)
[PASS] test_Constants_MaxLtv() (gas: 334)
[PASS] test_Constants_OracleStaleness() (gas: 315)
[PASS] test_Constants_RecoveryBuffer() (gas: 317)
[PASS] test_Constants_RiskParamRelationship() (gas: 382)
[PASS] test_Constants_SecondsPerYear() (gas: 360)
[PASS] test_Constants_SourceReserve() (gas: 350)
[PASS] test_Constants_WadPrecision() (gas: 291)
```

### 6. Bootstrap Script (`script/demo/check-env.sh`)

Validates:
- Foundry installation
- Environment variables (ETHEREUM_SEPOLIA_RPC, BASE_SEPOLIA_RPC, deployer keys)
- RPC endpoint connectivity and chain IDs
- Config file existence
- Folder structure
- Interface file existence
- Compilation success

Exit codes:
- 0: All checks passed
- 1: Errors found

## CLI Commands for Validation

```bash
# 1. Build all contracts
cd contracts && forge build

# 2. Run Slide 0 invariant tests
cd contracts && forge test --match-path test/demo/Setup.t.sol -v

# 3. Run environment check (will show warnings for missing RPC vars until Slide 5)
cd contracts && ./script/demo/check-env.sh

# 4. Run all tests
cd contracts && forge test -v
```

## Files Created/Modified

### New Files:
- `contracts/src/interfaces/ILendingLikeProtocol.sol`
- `contracts/src/interfaces/IDemoOracle.sol`
- `contracts/src/interfaces/IReprieveAdapter.sol`
- `contracts/src/libs/DemoConstants.sol`
- `contracts/config/ethereum-sepolia.json`
- `contracts/config/base-sepolia.json`
- `contracts/test/demo/Setup.t.sol`
- `contracts/script/demo/check-env.sh`

### Folders Created:
- `contracts/src/mocks/`
- `contracts/src/adapters/`
- `contracts/src/interfaces/`
- `contracts/src/libs/`
- `contracts/script/demo/`
- `contracts/test/demo/`
- `contracts/config/`

## Validation Checklist Status

- [x] `forge build` passes
- [x] `forge test --match-path test/demo/Setup.t.sol` passes
- [x] `script/demo/check-env.sh` exits with proper status codes
- [x] Project compiles with all new folders/interfaces
- [x] Shared constants load from one source only (`DemoConstants.sol`)
- [x] Bootstrap/config checks fail fast with actionable errors

## Next Steps

Proceed to **Slide 1: Core Primitives (ERC20 + Oracle)**

This slide will implement:
- `MockERC20.sol`: Mintable/burnable ERC20 for testing
- `MockPriceOracle.sol`: Owner-updated oracle with staleness tracking
