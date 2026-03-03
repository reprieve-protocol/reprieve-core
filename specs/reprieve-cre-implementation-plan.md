# Reprieve CRE Implementation Plan (Vertical Slides)

This plan implements [reprieve-cre-workflow-design.md](/Users/sniperman/code/reprieve/specs/reprieve-cre-workflow-design.md) with HTTP-primary triggers using a **base/common workflow foundation** plus **three separate profile workflows**:
- `CHAINLINK_API_GUARD_V1`
- `QUANT_FUNDING_OI_V1`
- `QUANT_BASIS_LIQUIDITY_V1`

`rescue-1` is treated as a template/bootstrap workflow, not the final production profile workflow.

## Workflow Layout (Target)

- Common shared module:
  - `cre/reprieve-common/*` (types, config parsing, ABI/io, planner core, envelopes, idempotency helpers)
- Profile workflows (separate deployable CREs):
  - `cre/reprieve-chainlink-api-guard-v1/*`
  - `cre/reprieve-quant-funding-oi-v1/*`
  - `cre/reprieve-quant-basis-liquidity-v1/*`
- Optional template:
  - `cre/rescue-1/*` (kept for scaffold/reference only)

## Slide 0 - CRE Foundation and Workflow Skeleton

**Status:** `Completed (code/build)`; `Simulation blocked locally by CRE auth/network`

### Development Scope
- Establish shared/base CRE foundation in `cre/reprieve-common`.
- Keep `cre/rescue-1` as template and create canonical skeleton for reusable handlers.
- Define base handler contract: HTTP primary, EVM log reconcile, cron watchdog.

### Build Tasks
- Implement typed config models and schema validation in `cre/reprieve-common/types.ts`.
- Implement shared handler/result contracts in `cre/reprieve-common/runtime.ts`.
- Add standard result envelope for all callbacks (`executionId`, decision, reason, tx refs, settlement state).
- Provide reusable trigger wiring helpers for HTTP/EVM-log/cron.

### Testing Scope
- Workflow boot test with valid config.
- Handler registration test for all trigger types.

### Script Scope
- `bun run build` target for each profile workflow directory.
- `cre workflow simulate ./reprieve-*-v1 --target=staging-settings` (cron trigger path).

### Acceptance Criteria
- Shared foundation initializes with all three handler types.
- Invalid config fails fast with clear error.

### Validation Checklist
- [x] `bun run build` passes in each profile workflow (`reprieve-chainlink-api-guard-v1`, `reprieve-quant-funding-oi-v1`, `reprieve-quant-basis-liquidity-v1`).
- [x] Simulate command runs without runtime panic (validated via cron-trigger simulation on all three profile workflows).
- [x] Trigger callbacks emit structured output format (JSON execution envelope skeleton).

---

## Slide 1 - Config Model and Per-User CRE Profiles

**Status:** `Completed`

### Development Scope
- Implement config model for **separate profile workflows** (not runtime profile switching).

### Build Tasks
- Define `BaseWorkflowConfig` in common module (trigger, thresholds, budgets, rescue, chains, cross-chain).
- Define profile-specific config extensions:
  - `ChainlinkApiGuardConfig`
  - `QuantFundingOiConfig`
  - `QuantBasisLiquidityConfig`
- Add config integrity checks:
  - required chain addresses
  - per-profile required external endpoints and weights
  - budget/threshold bounds
- Add profile workflow identity checks (each workflow accepts only its own config schema).

### Testing Scope
- Schema tests for valid/invalid profile configs.
- Profile-specific required-fields tests.

### Script Scope
- `scripts/cre/validate-config.ts` (or equivalent) for local preflight.

### Acceptance Criteria
- One workflow deployment maps to exactly one profile strategy.
- Profile selection is deployment-level (separate workflow), not runtime flag switching.

### Validation Checklist
- [x] All three profile configs pass schema validation.
- [x] Missing profile-required fields fail with deterministic errors.
- [x] Config parser outputs normalized runtime settings.

---

## Slide 2 - On-Chain IO Layer and Contract Integration

**Status:** `Completed`

### Development Scope
- Build robust shared read/write abstraction for adapters + Reprieve contracts.

### Build Tasks
- Implement `lib/contracts.ts` for:
  - adapter reads (`discoverPositions`, `healthFactor`, `availableCollateral`)
  - `RescueExecutor` checks (`rescueInProgress`)
  - rescue submission (`executeRescue`)
  - source log reads (`RescueLog` query/decode)
  - destination event reads (`CCIPReceiver`/router correlation)
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
- Workflow can reconcile destination terminal state for cross-chain legs.

### Validation Checklist
- [x] Adapter read bundle helper implemented (`discoverPositions`, `healthFactor`, `availableCollateral`) and returns normalized snapshot shape.
- [x] `rescueInProgress` read gate helper implemented in shared IO layer.
- [x] Rescue execution call helper serializes `RescuePlan` payload (`executeRescue`) and ABI compatibility script validates calldata encode.
- [x] Destination `CrossChainCompleted` / failure event decode helpers implemented and validated via ABI compatibility script topics/decode assumptions.

---

## Slide 3 - HTTP Primary Trigger, Auth, and Idempotency

### Development Scope
- Implement shared bot-driven HTTP entrypoint as primary monitoring/execution trigger for all profile workflows.

### Build Tasks
- Implement HTTP request parser + auth checks (`authorizedHttpKeys`).
- Add idempotent `executionId` generation.
- Add replay guard:
  - skip if same `executionId` already completed
  - skip if `rescueInProgress[user] == true`
  - skip if unresolved pending cross-chain message exists for the user/strategy
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
- [ ] Pending cross-chain execution blocks duplicate/competing submissions.

---

## Slide 4 - Risk Engine V1: CHAINLINK_API_GUARD_V1

**Status:** `Completed`

### Development Scope
- Implement `cre/reprieve-chainlink-api-guard-v1` workflow using shared foundation and V1 risk engine.

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
- [x] Verified report integrity check is enforced for API-sourced prices.
- [x] Fallback behavior is deterministic on verification/API failure (`mockPricesUsd` fallback; deterministic `ABORT` if unusable).
- [x] Effective HF + penalty path covered by deterministic computation helpers/tests.

---

## Slide 4B - API Guard V1 End-to-End Execution Flow

**Status:** `Completed`

### Development Scope
- Implement full `CHAINLINK_API_GUARD_V1` workflow path from trigger to rescue execution and cross-chain settlement reconciliation.

### Build Tasks
- HTTP primary trigger and cron fallback run through one orchestration path.
- Load per-user config + runtime guards:
  - auth via HTTP trigger keys (CRE capability)
  - deterministic `execId`
  - idempotency check (`getRescueStatus(execId)`)
  - lock check (`rescueInProgress(user)`)
  - optional pending cross-chain guard (`pendingExecId` + `ccipMessageId`)
- Read on-chain state via adapters (`discoverPositions`, `healthFactor`, `availableCollateral`).
- Fetch risk inputs (Chainlink API path + fallback policy) and compute risk decision.
- Build single-mode rescue plan (`TOP_UP` or `REPAY`) with:
  - same-chain-first source selection
  - optional cross-chain source selection
  - reserve-cap and budget clamp
  - no-swap compatibility checks for same-chain legs
- Optional pre-sim hook represented in metadata (`preSimSkipped: true`) for later Tenderly gate integration.
- Execute source-chain rescue (`executeRescue(plan)`), capture tx hash and optional CCIP message id.
- Reconcile settlement in EVM-log handler:
  - `CrossChainCompleted` => `DELIVERED_SUCCESS`
  - `CrossChainDestinationFailed` => `DELIVERED_FAILED`
  - `CrossChainInitiated` => `DISPATCHED`
  - same-chain `RescueCompleted` / `RescueFailed` tracking

### Testing Scope
- Compile + unit tests for V1 risk module.
- Cron simulation sanity for orchestration path.
- EVM-log decode/reconcile path compilation checks.

### Acceptance Criteria
- V1 can produce execution envelopes for monitor-only, dry-run, and execute modes.
- When rescue is required and runnable, workflow builds single-mode plan and can submit it.
- Cross-chain lifecycle is reflected by reconciliation settlement states from on-chain events.

### Validation Checklist
- [x] HTTP/cron triggers are wired into the same orchestration path.
- [x] Idempotency + in-progress checks are enforced before submit.
- [x] Planner emits single-mode plan and enforces same-chain no-swap compatibility.
- [x] Source execute path returns tx ref + settlement state (`DISPATCHED` for cross-chain).
- [x] EVM log handler maps destination terminal events to settlement state.

---

## Slide 4C - Backend Multi-Chain Position Data Plane (API Guard V1)

**Status:** `Completed (code/build)`

### Development Scope
- Move `CHAINLINK_API_GUARD_V1` position discovery from per-run on-chain adapter reads to backend aggregated position snapshots.
- Keep risk math and decisioning in CRE, but feed it with backend-synced cross-chain positions.

### Build Tasks
- Add CRE config fields for backend positions source:
  - `positionsApiBaseUrl`
  - `positionsApiPath`
  - `positionsApiMaxAgeSec`
  - optional `positionsApiKey`
- Integrate backend fetch in `risk-v1`:
  - call `/v1/positions/:address/risk-snapshot`
  - parse adapter positions, decimals, and freshness metadata
  - fail-closed (`ABORT`) when snapshot is stale or fetch fails
- Build adapter snapshots for planner from backend response (label/address/positions/source collateral).
- Output `decimalsByAsset` from risk layer so planner does not rely only on source-chain token decimal reads.
- Update planner to consume `decimalsByAsset` first, with on-chain decimals as fallback.

### Testing Scope
- Type/build verification for CRE workflow with new backend-driven source path.
- Validate that missing/stale backend snapshots return deterministic `ABORT`.
- Validate planner compiles/works with `decimalsByAsset` handoff.

### Acceptance Criteria
- API Guard can evaluate risk using backend multi-chain position state in one run.
- CRE no longer depends on reading all adapters on-chain each run to build position context.
- Snapshot freshness gate prevents acting on stale backend state.

### Validation Checklist
- [x] Backend `risk-snapshot` endpoint wired into API Guard config/model.
- [x] `risk-v1` fetches/parses backend snapshot and builds adapter snapshots.
- [x] Stale/fetch-failure behavior is fail-closed (`ABORT`).
- [x] Planner uses risk-layer `decimalsByAsset` before local chain fallback.

---

## Slide 5 - Risk Engine V2: QUANT_FUNDING_OI_V1

### Development Scope
- Implement `cre/reprieve-quant-funding-oi-v1` workflow using shared foundation + V2 risk model.

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
- Implement `cre/reprieve-quant-basis-liquidity-v1` workflow using shared foundation + V3 regime model.

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
- Build deterministic shared planner/execution pipeline consumed by all three profile workflows.

### Build Tasks
- Implement planner:
  - target debt sizing to recovery buffer
  - mode-aware action sizing (`TOP_UP` collateral sizing vs `REPAY` debt sizing)
  - source selection same-chain-first
  - multi-source fall-through (>2 positions)
  - reserve cap enforcement
  - enforce one mode per plan; no mixed-mode legs
  - enforce asset compatibility for no-swap executor semantics
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
- [ ] Mode constraint checks reject mixed or incompatible legs before submit.

---

## Slide 8 - Cross-Chain Reconciliation and Failure Routing

### Development Scope
- Track and reconcile cross-chain lifecycle using shared EVM log reconciliation module reused by all profile workflows.

### Build Tasks
- Decode and track events:
  - `RescueInitiated`
  - `CrossChainInitiated`
  - source `RescueCompleted` (dispatch-accepted signal only)
  - `RescueFailed`
  - `CrossChainCompleted`
  - `CrossChainDestinationFailed`
  - `EscrowCreated`
- Map `executionId` <-> `messageId` <-> source/destination tx.
- Track settlement state machine:
  - `DISPATCHED`
  - `DELIVERED_SUCCESS`
  - `DELIVERED_FAILED`
  - `TIMEOUT`
- Implement failure classifiers:
  - source fail pre-send
  - source fail post-withdraw
  - destination fail post-receive
  - relay/delivery timeout (demo two-network mock mode)
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
- Every cross-chain execution has an auditable terminal state (destination event based) or actionable recovery state.

### Validation Checklist
- [ ] messageId correlation works across chains.
- [ ] Source/destination failure classes are distinguishable.
- [ ] Recovery actions are generated for escrow branches.
- [ ] Source `RescueCompleted` alone is never treated as terminal success for cross-chain.

---

## Slide 9 - Cron Watchdog, Resilience, and Rate Controls

### Development Scope
- Implement shared watchdog behavior and operational safeguards, inherited by all profile workflows.

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
- Finalize full CRE stage verification and handoff artifacts for three profile workflows plus shared base.

### Build Tasks
- Build E2E matrix:
  - `chainlink-api-guard-v1` same-chain
  - `quant-funding-oi-v1` multi-position fallback
  - `quant-basis-liquidity-v1` cross-chain success (`execute` + relay + destination completion)
  - source failure and destination failure branches
  - cross-chain timeout classification branch
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
- Demo operators can run each profile workflow independently and explain behavioral differences clearly.

### Validation Checklist
- [ ] All E2E scenarios pass.
- [ ] Runbook steps execute without manual patching.
- [ ] Output artifacts include execution summaries, tx refs, message ids, and recovery states.

---

## Definition Of Done (CRE Stage)
- Shared base/common CRE module is implemented and reused by profile workflows.
- Three separate per-user CRE workflows are deployable:
  - `CHAINLINK_API_GUARD_V1`
  - `QUANT_FUNDING_OI_V1`
  - `QUANT_BASIS_LIQUIDITY_V1`
- Planner/executor integration works for same-chain and cross-chain paths in each workflow.
- Failure and recovery branches are fully classified and observable, with destination events as cross-chain settlement truth.
- System is demo-ready with reproducible scripts and clear operator runbook.
