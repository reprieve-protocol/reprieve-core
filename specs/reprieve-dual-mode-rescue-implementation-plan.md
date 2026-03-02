# Reprieve Dual-Mode Rescue Implementation Plan

## Objective
Add dual rescue execution modes so one rescue execution can run either:
- `TOP_UP` mode (increase target collateral), or
- `REPAY` mode (reduce target debt),
while enforcing **one mode per execution**.

## Scope
- Reprieve types/interfaces/executor/receiver updates.
- Reprieve tests for both modes and mixed-mode rejection.
- Scripts/runbook updates for operator-friendly mode selection.

## Non-Goals
- In-executor token swaps or DEX routing.
- CRE logic redesign (only contract interfaces/inputs needed by CRE).
- Economic strategy optimization beyond deterministic execution rules.

---

## Slide 1 - Type & Interface Model
Status: Completed

### Build
- Add `ReprieveTypes.RescueMode` enum: `TOP_UP`, `REPAY`.
- Add `mode` to `RescuePlan`.
- Add `mode` to `CCIPMessage`.
- Keep `RescueStep` fields for compatibility; mode determines which step fields are actionable.

### Acceptance Criteria
- Contracts compile with canonical mode fields.
- Backward-compatibility impact is explicit and limited to plan/message builders.

### Validation Checklist
- [x] `ReprieveTypes` includes `RescueMode`.
- [x] `RescuePlan` includes `mode`.
- [x] `CCIPMessage` includes `mode`.
- [x] Interface consumers compile after migration.

---

## Slide 2 - Executor Mode Gate (Same-Chain)
Status: Completed

### Build
- In `executeRescue`, enforce execution-level mode consistency:
  - entire plan runs in `plan.mode`.
  - mixed-mode behavior in one execution is disallowed by design (single dispatcher path).
- Add internal dispatch:
  - `TOP_UP` -> `supplyForRescue(user, collateralAsset, collateralAmount)`
  - `REPAY` -> `repayForRescue(user, debtAsset, debtAmount)`
- Preserve existing source withdraw + escrow handling.

### Acceptance Criteria
- Same-chain rescue works in both modes.
- Invalid per-mode params (zero amount, unsupported asset) fail deterministically.

### Validation Checklist
- [x] Same-chain `TOP_UP` path succeeds.
- [x] Same-chain `REPAY` path succeeds.
- [x] Mode-specific validation reverts correctly.
- [x] Post-withdraw failure still escrows.

---

## Slide 3 - Cross-Chain Payload & Completion Dispatch
Status: Completed

### Build
- Encode `mode` in CCIP payload.
- For `TOP_UP`, payload/token amount uses `collateralAsset/collateralAmount`.
- For `REPAY`, payload/token amount uses `debtAsset/debtAmount`.
- Destination completion dispatches by payload mode:
  - `TOP_UP` -> `supplyForRescue`
  - `REPAY` -> `repayForRescue`

### Acceptance Criteria
- Cross-chain completion behavior matches selected mode.
- Payload/token mismatch cannot silently pass.

### Validation Checklist
- [x] CCIP payload includes mode + correct asset/amount.
- [x] Destination executes top-up in `TOP_UP`.
- [x] Destination executes repay in `REPAY`.
- [x] Mode/asset mismatch routes to failure handling.

---

## Slide 4 - Hedging Safety Rules
Status: Completed

### Build
- Document and enforce deterministic constraints:
  - no swap inside executor,
  - target action asset must be directly available from withdrawn/bridged token,
  - otherwise fail + escrow.
- Add explicit hedging examples:
  - WETH dump branch: withdraw USDC source -> repay USDC target debt.
  - WETH pump branch: withdraw WETH source -> repay WETH target debt.

### Acceptance Criteria
- Repay-based hedge scenarios are representable without ad hoc logic.
- Unsupported conversion paths fail safely.

### Validation Checklist
- [x] Hedge path example tests pass in `REPAY` mode.
- [x] Unsupported conversion test fails and escrows.
- [x] Logs clearly indicate mode used.

---

## Slide 5 - Test Migration
Status: Completed

### Build
- Update reprieve unit/integration tests to cover both modes:
  - `RescueExecutorTest`
  - `CrossChainIntegrationTest`
  - `FailureScenariosTest`
  - `CCIPReceiverTest` (mode decode/dispatch behavior)
- Add mixed-mode guard test:
  - one execution cannot combine `TOP_UP` + `REPAY`.

### Acceptance Criteria
- Existing top-up behavior remains green.
- Repay-mode behavior is fully covered in same-chain and cross-chain paths.

### Validation Checklist
- [x] `TOP_UP` tests pass.
- [x] `REPAY` tests pass.
- [x] Mixed-mode rejection test passes.
- [x] Escrow recovery tests remain green.

---

## Slide 6 - Script & Runbook UX
Status: Completed

### Build
- Add mode parameterization in scripts:
  - `RESCUE_MODE=TOP_UP|REPAY`
- Add mode-specific env defaults:
  - top-up amounts/assets
  - repay amounts/assets
- Update runbook with:
  - when to use each mode,
  - hedging scenario examples,
  - required env inputs per mode.

### Acceptance Criteria
- Operator can run demos without manual code edits.
- Mode selection is explicit and hard to misuse.

### Validation Checklist
- [x] Same-chain script runs in both modes.
- [x] Cross-chain script runs in both modes.
- [x] `ops.sh` forwards mode/env correctly.
- [x] Runbook examples are accurate.

---

## Slide 7 - End-to-End Validation Gate
Status: Completed

### Build
- Run focused suites and compile gate after migration.

### Acceptance Criteria
- Core reprieve behavior is stable with dual-mode support.

### Validation Checklist
- [x] `forge test --match-contract RescueExecutorTest`
- [x] `forge test --match-contract CrossChainIntegrationTest`
- [x] `forge test --match-contract CCIPReceiverTest`
- [x] `forge test --match-contract FailureScenariosTest`
- [x] `forge build --skip test`

---

## Suggested Execution Order
1. Slide 1
2. Slide 2
3. Slide 3
4. Slide 5
5. Slide 6
6. Slide 7

## Main Risks
- Type migration touches all plan/message builders in scripts/tests.
- Existing scripts may still assume top-up-only defaults.
- Cross-chain mode dispatch must remain fully deterministic to avoid stranded funds.
