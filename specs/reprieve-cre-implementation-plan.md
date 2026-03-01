# Reprieve CRE Implementation Plan (Vertical Slides)

This plan implements [reprieve-cre-workflow-design.md](/Users/sniperman/code/reprieve/specs/reprieve-cre-workflow-design.md) with HTTP-primary triggers and per-user customized CRE profiles.

## Slide 0 - CRE Foundation and Workflow Skeleton

### Development Scope
- Convert `cre/rescue-1` from hello-world to a production skeleton.
- Establish handler structure: HTTP primary, EVM log reconcile, cron watchdog.

### Build Tasks
- Implement typed `Config` and schema validation in `cre/rescue-1/types.ts`.
- Refactor `main.ts` to register:
  - HTTP trigger callback
  - EVM log trigger callback
  - cron watchdog callback
- Add standard result envelope for all callbacks (`executionId`, decision, reason, tx refs).

### Testing Scope
- Workflow boot test with valid config.
- Handler registration test for all trigger types.

### Script Scope
- `bun run build` target for `cre/rescue-1`.
- `cre workflow simulate ./cre/rescue-1 --target=staging-settings`.

### Acceptance Criteria
- Workflow initializes with all three handlers.
- Invalid config fails fast with clear error.

### Validation Checklist
- [ ] `bun run build` passes in `cre/rescue-1`.
- [ ] Simulate command runs without runtime panic.
- [ ] Trigger callbacks emit structured output format.

---

## Slide 1 - Config Model and Per-User CRE Profiles

### Development Scope
- Implement profile-aware config for per-user custom CREs.

### Build Tasks
- Add profile enum:
  - `CHAINLINK_API_GUARD_V1`
  - `QUANT_FUNDING_OI_V1`
  - `QUANT_BASIS_LIQUIDITY_V1`
- Add `trigger`, `thresholds`, `budgets`, `rescue`, `chains`, `quant` sections.
- Add config integrity checks:
  - required chain addresses
  - profile-specific required endpoints
  - budget/threshold bounds

### Testing Scope
- Schema tests for valid/invalid profile configs.
- Profile-specific required-fields tests.

### Script Scope
- `scripts/cre/validate-config.ts` (or equivalent) for local preflight.

### Acceptance Criteria
- One workflow config can fully define one user strategy.
- Profile switching is config-only (no code changes required).

### Validation Checklist
- [ ] All three profile configs pass schema validation.
- [ ] Missing profile-required fields fail with deterministic errors.
- [ ] Config parser outputs normalized runtime settings.

---

## Slide 2 - On-Chain IO Layer and Contract Integration

### Development Scope
- Build robust read/write abstraction for adapters + Reprieve contracts.

### Build Tasks
- Implement `lib/contracts.ts` for:
  - adapter reads (`discoverPositions`, `healthFactor`, `availableCollateral`)
  - `RescueExecutor` checks (`rescueInProgress`)
  - rescue submission (`executeRescue`)
  - log reads (`RescueLog` query/decode)
- Add chain routing via `chainSelectorName`.
- Add ABI wrappers for stable decode/encode paths.

### Testing Scope
- Unit tests with mocked EVM client responses.
- ABI compatibility tests against deployed contract interfaces.

### Script Scope
- `scripts/cre/check-abi-compat.ts` to validate selectors and decode assumptions.

### Acceptance Criteria
- Workflow can read all required state from both target chains.
- Workflow can submit rescue tx with correct calldata.

### Validation Checklist
- [ ] Adapter read bundle returns complete position snapshot.
- [ ] `rescueInProgress` read gate works.
- [ ] Rescue execution call serializes expected plan payload.

---

## Slide 3 - HTTP Primary Trigger, Auth, and Idempotency

### Development Scope
- Implement bot-driven HTTP entrypoint as primary monitoring/execution trigger.

### Build Tasks
- Implement HTTP request parser + auth checks (`authorizedHttpKeys`).
- Add idempotent `executionId` generation.
- Add replay guard:
  - skip if same `executionId` already completed
  - skip if `rescueInProgress[user] == true`
- Add request modes:
  - `monitor_only`
  - `execute`
  - `dry_run`

### Testing Scope
- Auth reject tests.
- Duplicate request/replay tests.
- in-progress lock skip tests.

### Script Scope
- `scripts/cre/send-http-trigger.sh` for bot/operator testing.

### Acceptance Criteria
- Only authorized bots can trigger execution.
- Duplicate/resubmitted requests do not create duplicate rescues.

### Validation Checklist
- [ ] Unauthorized HTTP requests are rejected.
- [ ] Duplicate executionId is ignored safely.
- [ ] `monitor_only` and `dry_run` never submit on-chain tx.

---

## Slide 4 - Risk Engine V1: CHAINLINK_API_GUARD_V1

### Development Scope
- Implement baseline CRE risk engine using Chainlink off-chain price delivery + verification.

### Build Tasks
- Build chainlink price fetch module (API/report path).
- Verify report/integrity before using price.
- Build aggregate HF computation from adapter positions + verified prices.
- Implement slope/staleness penalties for tighter effective HF.
- Decision output:
  - `NO_ACTION`
  - `RESCUE_SAME_CHAIN`
  - `RESCUE_CROSS_CHAIN`
  - `ABORT`

### Testing Scope
- Verified price happy path.
- report verify failure path (fallback/no-trade mode).
- slope penalty trigger sensitivity tests.

### Script Scope
- `scripts/cre/run-profile-v1.sh` simulation runner.

### Acceptance Criteria
- V1 can trigger rescue earlier than pure point-in-time HF threshold in deterioration scenarios.
- Invalid or stale price reports are safely handled.

### Validation Checklist
- [ ] Verified report is required before price is accepted.
- [ ] Fallback behavior is deterministic on verification failure.
- [ ] Effective HF output is reproducible for fixed inputs.

---

## Slide 5 - Risk Engine V2: QUANT_FUNDING_OI_V1

### Development Scope
- Add funding/open-interest stress model on top of V1 verified price path.

### Build Tasks
- Integrate Binance USD-M + Bybit endpoints for:
  - funding
  - open interest
- Compute normalized stress score:
  - funding level + acceleration
  - OI expansion
  - venue divergence penalty
- Convert score into dynamic threshold uplift.

### Testing Scope
- Stress score component tests.
- Dynamic threshold uplift bounds tests.
- Quant timeout/degradation to V1 tests.

### Script Scope
- `scripts/cre/run-profile-v2.sh` with mock/stub market-data fixtures.

### Acceptance Criteria
- V2 triggers earlier under leverage build-up even when base HF has not yet crossed static threshold.
- Quant API failure degrades safely to V1 behavior.

### Validation Checklist
- [ ] Score components are bounded and unit-tested.
- [ ] Threshold uplift range is enforced.
- [ ] Quant failure path falls back to V1 without crash.

---

## Slide 6 - Risk Engine V3: QUANT_BASIS_LIQUIDITY_V1

### Development Scope
- Implement advanced regime model using basis + flow + liquidity stress.

### Build Tasks
- Integrate additional endpoints:
  - basis
  - open-interest history
  - taker long/short flow
- Build regime classifier.
- Implement two-stage action policy:
  - pre-emptive partial rescue
  - defensive full rescue (including cross-chain legs)

### Testing Scope
- Regime classifier tests (normal/stress/extreme).
- Stage transition tests (pre-emptive -> defensive).
- Cross-venue disagreement handling tests.

### Script Scope
- `scripts/cre/run-profile-v3.sh`.

### Acceptance Criteria
- V3 can trigger earlier and scale rescue intensity with detected regime severity.
- Stage transitions are deterministic and auditable.

### Validation Checklist
- [ ] Regime score and stage thresholds are tested.
- [ ] Pre-emptive mode executes smaller rescue legs.
- [ ] Defensive mode executes full plan when required.

---

## Slide 7 - Rescue Planner and Execution Orchestration

### Development Scope
- Build deterministic rescue plan generation and execution pipeline.

### Build Tasks
- Implement planner:
  - target debt sizing to recovery buffer
  - source selection same-chain-first
  - multi-source fall-through (>2 positions)
  - reserve cap enforcement
- Integrate optional Tenderly pre-sim gate.
- Execute via `RescueExecutor.executeRescue(plan)`.

### Testing Scope
- Same-chain single-source plan tests.
- Multi-source fallback tests.
- Cross-chain leg inclusion tests.
- Simulation fail-closed tests.

### Script Scope
- `scripts/cre/run-planner-scenarios.sh`.

### Acceptance Criteria
- Planner outputs stable plans for identical snapshots.
- Execution improves target safety metrics when feasible.

### Validation Checklist
- [ ] Plan generation is deterministic for fixed snapshot hash.
- [ ] Source #1 insufficient path falls through to later sources.
- [ ] Tenderly fail-closed mode aborts unsafe plan.

---

## Slide 8 - Cross-Chain Reconciliation and Failure Routing

### Development Scope
- Track and reconcile cross-chain lifecycle using EVM log triggers.

### Build Tasks
- Decode and track events:
  - `RescueInitiated`
  - `CrossChainInitiated`
  - `RescueCompleted`
  - `RescueFailed`
  - `Escrowed`
- Map `executionId` <-> `messageId` <-> source/destination tx.
- Implement failure classifiers:
  - source fail pre-send
  - source fail post-withdraw
  - destination fail post-receive
- Route recovery suggestions:
  - retry
  - claim escrow

### Testing Scope
- Event decode and correlation tests.
- Failure-branch classification tests.
- Escrow recovery recommendation tests.

### Script Scope
- `scripts/cre/reconcile-execution.sh`.

### Acceptance Criteria
- Every cross-chain execution has an auditable terminal state or actionable recovery state.

### Validation Checklist
- [ ] messageId correlation works across chains.
- [ ] Source/destination failure classes are distinguishable.
- [ ] Recovery actions are generated for escrow branches.

---

## Slide 9 - Cron Watchdog, Resilience, and Rate Controls

### Development Scope
- Implement watchdog behavior and operational safeguards.

### Build Tasks
- Add cron fallback handler (2-5 min default).
- Add rate controls:
  - per-user trigger cooldown
  - max concurrent executions
  - per-cycle read/write budget guards
- Add timeout/retry policy for external APIs.

### Testing Scope
- Bot outage simulation -> cron watchdog continuity.
- API timeout/retry behavior tests.
- Cooldown and concurrency tests.

### Script Scope
- `scripts/cre/run-watchdog-test.sh`.

### Acceptance Criteria
- Workflow remains operational when HTTP bot layer is degraded.
- No runaway execution loops under repeated failures.

### Validation Checklist
- [ ] Cron watchdog enters monitor mode when HTTP is unavailable.
- [ ] Cooldown prevents trigger storms.
- [ ] Retry limits prevent infinite loops.

---

## Slide 10 - E2E Validation, Demo Runbook, and Handoff

### Development Scope
- Finalize full CRE stage verification and handoff artifacts.

### Build Tasks
- Build E2E matrix:
  - profile v1 same-chain
  - profile v2 multi-position fallback
  - profile v3 cross-chain success
  - source failure and destination failure branches
- Produce operator runbook:
  - how bots trigger HTTP
  - how to monitor execution
  - how to recover escrow cases

### Testing Scope
- Full simulation set with fixed fixtures.
- Deterministic replay checks by execution ID.
- Output schema checks for frontend/backend consumers.

### Script Scope
- `scripts/cre/run-all-e2e.sh`
- `scripts/cre/demo-runbook-check.sh`

### Acceptance Criteria
- One-command test pack verifies all critical CRE paths.
- Demo operators can run and explain profile differences clearly.

### Validation Checklist
- [ ] All E2E scenarios pass.
- [ ] Runbook steps execute without manual patching.
- [ ] Output artifacts include execution summaries, tx refs, message ids, and recovery states.

---

## Definition Of Done (CRE Stage)
- Per-user CRE workflow is live with HTTP primary trigger and cron watchdog.
- Three profile logics are implemented and selectable by config.
- Planner/executor integration works for same-chain and cross-chain paths.
- Failure and recovery branches are fully classified and observable.
- System is demo-ready with reproducible scripts and clear operator runbook.
