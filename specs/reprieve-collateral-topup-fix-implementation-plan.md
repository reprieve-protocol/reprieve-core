# Reprieve Collateral Top-Up Fix Implementation Plan

## Objective
Fix Reprieve rescue execution to use **collateral top-up** (not debt repay) so same-chain and cross-chain flows are economically consistent without synthetic asset conversion.

## Scope
- Reprieve contracts + adapters + required mock protocol capabilities.
- Reprieve tests covering success/failure paths.
- Reprieve scripts/env updates where behavior changed.

## Non-Goals
- DEX pricing/slippage modeling.
- Production bridge/token pool mechanics.
- CRE redesign (only contract interface assumptions that CRE uses).

---

## Slide 1 - Contract Interface Migration
Status: Completed

### Build
- Extend adapter interface with top-up primitive:
  - `supplyForRescue(address user, address asset, uint256 amount)`
- Keep existing `repayForRescue` for backward compatibility in adapter/unit tests and optional fallback workflows.

### Acceptance Criteria
- All adapters compile against new interface.
- No existing interface users break at compile time after migration updates.

### Validation Checklist
- [x] `IReprieveAdapter` includes `supplyForRescue`.
- [x] Adapters implement `supplyForRescue`.
- [x] Failing/mock adapters in tests/scripts also implement new method.

---

## Slide 2 - Adapter + Mock Protocol Top-Up Support
Status: Completed

### Build
- `AaveLikeAdapter`: implement top-up via `supply(..., onBehalfOf=user, ...)`.
- `CompoundLikeAdapter`: implement top-up via `mintFor(onBehalfOf, ...)` (or compatible on-behalf supply path).
- `MorphoLikeAdapter`: implement top-up via `supplyCollateral(..., onBehalfOf=user, ...)`.
- `MockCompoundMarket`: add on-behalf collateral supply entrypoint required by adapter.

### Acceptance Criteria
- For each protocol flavor, adapter top-up increases target user collateral balance/position in protocol state.
- Unsupported asset or zero-amount top-up reverts.

### Validation Checklist
- [x] Aave top-up path deposits collateral for `user`.
- [x] Compound top-up path deposits collateral for `user`.
- [x] Morpho top-up path deposits collateral for `user`.
- [x] Adapter-level negative tests pass.

---

## Slide 3 - RescueExecutor Logic Switch (Core Fix)
Status: Completed

### Build
- Same-chain leg:
  - keep source `withdrawForRescue`.
  - replace target repay call with `supplyForRescue(user, collateralAsset, collateralAmount)`.
- Cross-chain message semantics:
  - payload `asset/amount` must represent **collateral top-up asset/amount**.
  - destination completion calls `supplyForRescue`, not `repayForRescue`.
- Keep failure handling unchanged (escrow on post-withdraw or destination-execution failure).

### Acceptance Criteria
- Same-chain rescue no longer requires destination debt-token liquidity in executor.
- Cross-chain success no longer requires source->destination synthetic token-class mapping (unless intentionally configured).

### Validation Checklist
- [x] `_executeSameChainStep` uses top-up method.
- [x] `_sendCCIPMessage` payload asset aligns with transferred collateral asset.
- [x] `completeCrossChainLeg` uses top-up method.
- [x] Failure branches still escrow and unlock correctly.

---

## Slide 4 - CCIP Mapping Consistency Rules
Status: Completed

### Build
- Define/default lane mapping as same-asset class (`WETH->WETH`, `USDC->USDC`) for realistic behavior.
- Preserve configurable mapping for mock experiments, but document that cross-asset mapping is synthetic.

### Acceptance Criteria
- Default demo path works with same-asset mapping.
- If mapping and payload asset mismatch, flow fails deterministically and goes through failure handling.

### Validation Checklist
- [x] Happy path test uses same-asset mapping.
- [x] Mismatch test triggers failure/escrow.

---

## Slide 5 - Test Migration (Reprieve)
Status: Completed

### Build
- Update `CrossChainIntegration.t.sol` to assert collateral top-up outcomes:
  - destination collateral increases,
  - debt unchanged (unless a separate repay action is explicitly tested).
- Update failure scenario helpers (`FailingAdapter`) to fail top-up method.
- Add/adjust adapter tests for `supplyForRescue`.

### Acceptance Criteria
- Reprieve same-chain and cross-chain tests reflect top-up semantics.
- No tests rely on synthetic collateral->debt conversion for success.

### Validation Checklist
- [x] `CrossChainIntegration` validates top-up success.
- [x] Destination-failure path still escrowed/recoverable.
- [x] `RescueExecutor` tests remain valid under top-up model.
- [x] Adapter tests include top-up coverage.

---

## Slide 6 - Script & Ops Alignment
Status: Completed

### Build
- Update scenario scripts (`RunSameChainRescue`, `RunCrossChainRescue`, failure runners) to use top-up assumptions.
- Update lane wiring defaults/examples for realistic mapping.
- Update runbook/env guidance accordingly.

### Acceptance Criteria
- Operator can run same-chain and cross-chain top-up demos without manual contract patching.
- Failure scenario scripts still produce escrow-recovery workflow.

### Validation Checklist
- [x] Script defaults use consistent collateral top-up values.
- [x] Ops commands still succeed with updated assumptions.
- [x] Runbook examples match current flow.

---

## Slide 7 - End-to-End Validation Gate
Status: Completed

### Build
- Run focused and then broad test suites after migration.

### Acceptance Criteria
- Core Reprieve suites pass under top-up semantics.

### Validation Checklist
- [x] `forge test --match-contract RescueExecutorTest`
- [x] `forge test --match-contract CrossChainIntegrationTest`
- [x] `forge test --match-contract CCIPReceiverTest`
- [x] `forge test --match-contract FailureScenariosTest`
- [x] `forge build --skip test`

---

## Execution Order
1. Slide 1
2. Slide 2
3. Slide 3
4. Slide 5
5. Slide 6
6. Slide 7

## Risks
- Interface migration touches many tests and helper mocks.
- Compound-like mock may need on-behalf supply support for clean top-up semantics.
- Existing scripts may encode repay-oriented variable names that must be normalized to avoid operator confusion.
