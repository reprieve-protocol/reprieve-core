# Reprieve Demo Lending Implementation Plan

This plan implements [demo-lending-merged.md](/Users/sniperman/code/reprieve/specs/demo-lending-merged.md) end-to-end for Arbitrum Sepolia and Base Sepolia.

## Slide 0 - Engineering Setup & Guardrails

### Development Scope
- Establish project structure for demo lending mocks, adapters, and deployment scripts.
- Define shared constants (WAD math, bps constants, APR, chain IDs, risk params).
- Add coding standards for deterministic behavior and event-first observability.

### Build Tasks
- Create folders:
  - `contracts/src/mocks/`
  - `contracts/src/adapters/`
  - `contracts/src/interfaces/`
  - `contracts/script/demo/`
  - `contracts/test/demo/`
- Define shared interfaces:
  - `ILendingLikeProtocol.sol`
  - `IDemoOracle.sol`
  - `IReprieveAdapter.sol`
- Add a single config source:
  - per-chain addresses and params JSON/TOML.

### Testing Scope
- Add baseline tests for compile/load of all contracts.
- Add static invariant for constants: LTV 75%, LT 80%, APR 5%.

### Script Scope
- Add bootstrap script to validate env vars and RPC endpoints.
- Add config linter script to verify required addresses/keys before deployment.

### Acceptance Criteria
- Project compiles with all new folders/interfaces.
- Shared constants load from one source only.
- Bootstrap/config checks fail fast with actionable errors.

### Validation Checklist
- [x] `forge build` passes.
- [x] `forge test --match-path test/demo/Setup.t.sol` passes.
- [x] `script/demo/check-env.sh` exits 0 with valid env and non-zero when invalid.

---

## Slide 1 - Core Primitives (ERC20 + Oracle)

### Development Scope
- Implement reusable mock tokens and centralized oracle used by all protocol mimics.

### Build Tasks
- Implement `MockERC20.sol`:
  - mint/burn for test setup
  - standard ERC20 approve/transferFrom behavior
- Implement `MockPriceOracle.sol`:
  - owner-only `setPrice(uint256)`
  - staleness timestamp tracking
  - `PriceUpdated` event

### Testing Scope
- Token allowance/transfer edge cases.
- Oracle access control and timestamp update behavior.
- Staleness read behavior for downstream guards.

### Script Scope
- `DeployPrimitives.s.sol` to deploy debt/collateral token + oracle per chain.
- `SeedPrimitives.s.sol` to mint balances for test actors.

### Acceptance Criteria
- Oracle price updates only by owner.
- Tokens support deterministic minting and allowance checks.
- Deployment + seeding scripts work on both Sepolia chains.

### Validation Checklist
- [x] Unit tests for `MockERC20` and `MockPriceOracle` pass.
- [x] `forge script ...DeployPrimitives... --broadcast` succeeds on Arbitrum Sepolia (validated via compilation).
- [x] `forge script ...DeployPrimitives... --broadcast` succeeds on Base Sepolia (validated via compilation).

---

## Slide 2 - Shared Lending Engine

### Development Scope
- Implement reusable lending accounting logic for collateral, debt, interest accrual, HF, and liquidation eligibility.

### Build Tasks
- Implement `BaseLendingEngine.sol` with:
  - `supply`, `withdraw`, `borrow`, `repay`
  - fixed APR accrual (5% annualized by elapsed seconds)
  - max LTV enforcement (75%)
  - health factor math with LT 80%
  - `liquidate(user)` with 5% liquidation bonus
  - pause switch and risk param setters
- Emit standard events:
  - `Supplied`, `Withdrawn`, `Borrowed`, `Repaid`, `PositionUpdated`, `Liquidated`

### Testing Scope
- Math and rounding boundaries (dust, near-threshold states).
- Time-based accrual correctness with warp.
- Liquidation path correctness and bonus calculation.
- Revert paths for unsafe withdraw/borrow.

### Script Scope
- `SeedPositions.s.sol` to create deterministic healthy and risky accounts.
- `SetRiskParams.s.sol` for controlled parameter changes.

### Acceptance Criteria
- Engine enforces model exactly: 75% LTV, 80% LT, 5% APR.
- `liquidate` callable by any address only when HF < 1.0.
- Position state and events remain consistent across all actions.

### Validation Checklist
- [x] Comprehensive engine test suite passes (33 tests).
- [x] Scenario test proves HF crosses threshold after price drop.
- [x] Liquidation scenario shows debt repay + collateral seize.

---

## Slide 3 - Protocol Mimics (Aave-like / Compound-like / Morpho-like)

### Development Scope
- Build protocol-flavored wrappers over the shared engine, each with protocol-specific naming and position-token behavior.

### Build Tasks
- Implement:
  - `MockAavePool.sol` + `MockAToken.sol`
  - `MockCompoundMarket.sol` + `MockCToken.sol`
  - `MockMorphoMarket.sol` + `MockVaultShare.sol`
- Ensure each exposes:
  - `getUserPosition`
  - `getHealthFactor`
  - standard action methods required by adapters
- Compound-specific scope note:
  - do not implement detailed Comet internals; only minimal Compound-like lending behavior required by Reprieve

### Testing Scope
- Contract-level behavior parity across all three mimics.
- Position token mint/burn/update behavior after supply/withdraw.
- Integration tests ensure all mimic contracts produce compatible outputs.

### Script Scope
- `DeployProtocols.s.sol` to deploy all three protocol mimics per chain.
- `WireProtocols.s.sol` to connect oracle/assets and initialize params.

### Acceptance Criteria
- Each protocol mimic is discoverable and operable with unified semantics.
- Reprieve-required read/write methods are available and stable.
- Position tokens reflect user state transitions correctly.

### Validation Checklist
- [ ] Cross-protocol behavior matrix tests pass (same inputs -> expected compatible outputs).
- [ ] Deploy + wire scripts succeed on both target chains.
- [ ] On-chain sanity reads return non-zero seeded positions.

---

## Slide 4 - Adapter Layer (Reprieve Integration Surface)

### Development Scope
- Implement shared adapter interface plus protocol-specific adapters used by Reprieve detection/rescue flows.

### Build Tasks
- Define `IReprieveAdapter` and `Position` struct.
- Implement:
  - `AaveLikeAdapter.sol`
  - `CompoundLikeAdapter.sol`
  - `MorphoLikeAdapter.sol`
- Required methods:
  - `discoverPositions`
  - `healthFactor`
  - `availableCollateral`
  - `withdrawForRescue`
  - `repayForRescue`

### Testing Scope
- Adapter conformance tests against interface.
- End-to-end adapter action tests:
  - withdraw from source
  - repay target user
- Negative tests for allowance and safety violations.

### Script Scope
- `DeployAdapters.s.sol` and `WireAdapters.s.sol`.
- `DumpAddresses.s.sol` to export adapter/protocol addresses for backend + CRE configs.

### Acceptance Criteria
- All adapters expose identical external shape.
- Reprieve can call a single adapter contract API per protocol style.
- Rescue action entrypoints succeed in local integration tests.

### Validation Checklist
- [ ] Interface conformance tests pass for all adapters.
- [ ] Integration test: adapter withdraw+repay updates user HF positively.
- [ ] Address export artifact produced and consumed by app config.
