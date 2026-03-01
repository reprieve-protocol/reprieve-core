# Reprieve CRE Workflow Definition and Logic Design

This document defines the CRE stage for Reprieve after lending mocks/adapters and Reprieve protocol contracts are in place.

Related specs:
- [reprieve-contracts-design.md](/Users/sniperman/code/reprieve/specs/reprieve-contracts-design.md)
- [reprieve-contracts-implementation-plan.md](/Users/sniperman/code/reprieve/specs/reprieve-contracts-implementation-plan.md)
- [ccip-smart-contract-dev-guide.md](/Users/sniperman/code/reprieve/specs/ccip-smart-contract-dev-guide.md)

---

## 1) Scope and Principles

### Goal
Implement a per-user CRE workflow that performs:
- detect risk
- compute rescue plan
- execute rescue through Reprieve contracts
- verify and record outcomes

### Non-goals (this stage)
- Rewriting risk logic into on-chain contracts.
- Multi-user monolithic workflow with shared mutable state.
- Institutional policy/RBAC layers.

### CRE principles to follow
- Stateless callback executions (derive decisions from fresh reads every run).
- Trigger + callback architecture (`handler(trigger, callback)`).
- Parallel reads where possible, bounded by CRE capability quotas.
- Deterministic planning from a single snapshot to avoid divergent outputs.

---

## 2) Workflow Topology

## Workflow A - `reprieve-user-rescue`

Per-user workflow (one strategy = one workflow deployment).

Handlers:
1. `http` handler (primary monitor-and-act loop)
- Triggered by external monitoring bots or backend scheduler.
- Performs full risk snapshot, plan generation, and rescue execution decision.
- This is the main production trigger path for active monitoring.

2. `evm log` handler (state reconciliation)
- Listens to `RescueExecutor`/`RescueLog` events.
- Reconciles in-flight rescue state and updates proof/summary outputs.

3. `cron` handler (watchdog fallback)
- Low-frequency safety trigger (for example every 2-5 minutes).
- Used as a backstop if bot-triggered HTTP calls are delayed or unavailable.
- Can be configured as monitor-only or full execution mode.

Why this topology:
- HTTP trigger enables proactive bot-driven monitoring and low latency reactions.
- EVM log trigger reduces time-to-finality for cross-chain lifecycle tracking.
- Cron watchdog prevents blind spots when off-chain trigger infrastructure degrades.
- Keeps one workflow per user while still supporting event-driven reconciliation.

---

## 3) On-Chain Integration Map

Workflow reads/writes these contracts (per chain):
- `AdapterRegistry`
- `AaveLikeAdapter`
- `CompoundLikeAdapter`
- `MorphoLikeAdapter`
- `RescueExecutor`
- `RescueLog`
- `RescueEscrow`
- `HealthMonitor` (optional write for snapshot/proof)

Cross-chain:
- Initiation through source-chain `RescueExecutor`.
- Completion via destination `CCIPReceiver` + destination `RescueExecutor`.

---

## 4) Config Model (Per User Workflow)

```ts
type WorkflowConfig = {
  user: `0x${string}`;
  trigger: {
    mode: "HTTP_PRIMARY";
    cronWatchdogSchedule: string;
    authorizedHttpKeys: Array<`0x${string}`>;
  };
  strategyId: string;
  profile: "CHAINLINK_API_GUARD_V1" | "QUANT_FUNDING_OI_V1" | "QUANT_BASIS_LIQUIDITY_V1";
  thresholds: {
    aggregateHf: string;          // e.g. "1.30"
    emergencyHf: string;          // e.g. "1.10"
    recoveryBufferBps: number;    // 11000
    staleDataTimeoutSec: number;  // 1800
  };
  budgets: {
    perRescueWei: string;
    dailyWei: string;
  };
  rescue: {
    sourceReserveFactorBps: number; // 2000 => keep 20% reserve
    maxSourcesPerPlan: number;      // e.g. 5
    tenderlyEnabled: boolean;
    tenderlyFailClosed: boolean;    // true in demo
  };
  chains: Array<{
    name: string;
    chainSelectorName: string;
    chainId: number;
    adapterRegistry: `0x${string}`;
    rescueExecutor: `0x${string}`;
    rescueLog: `0x${string}`;
    rescueEscrow: `0x${string}`;
    healthMonitor?: `0x${string}`;
    adapters: {
      aaveLike: `0x${string}`;
      compoundLike: `0x${string}`;
      morphoLike: `0x${string}`;
    };
    dataFeeds: {
      collateralUsd: `0x${string}`;
      debtUsd: `0x${string}`;
    };
  }>;
  quant: {
    endpoint: string;
    timeoutMs: number;
    sources: {
      chainlinkStreamsApiBaseUrl: string;
      binanceUsdMBaseUrl: string;
      bybitV5BaseUrl: string;
    };
    weights: {
      volatility: number;
      funding: number;
      oi: number;
      spread: number;
    };
    failOpen: boolean; // if false, skip rescue decision when quant unavailable
  };
}
```

Design rule:
- Config must be chain-explicit and user-explicit to avoid implicit defaults.

---

## 5) Data Model for Runtime Logic

```ts
type PositionSnapshot = {
  chain: string;
  protocolId: "AAVE_LIKE" | "COMPOUND_LIKE" | "MORPHO_LIKE";
  adapter: `0x${string}`;
  collateralAsset: `0x${string}`;
  debtAsset: `0x${string}`;
  collateralAmount: bigint;
  debtAmount: bigint;
  healthFactorWad: bigint;
  availableCollateral: bigint;
  timestampSec: number;
};

type RiskSnapshot = {
  aggregateHfWad: bigint;
  minPositionHfWad: bigint;
  urgent: boolean;
  stale: boolean;
  quantScoreBps: number;
  positions: PositionSnapshot[];
};

type RescueLeg = {
  sourceChain: string;
  sourceProtocolId: string;
  targetChain: string;
  targetProtocolId: string;
  collateralAsset: `0x${string}`;
  debtAsset: `0x${string}`;
  amount: bigint;
  crossChain: boolean;
};

type RescuePlan = {
  executionId: `0x${string}`;
  user: `0x${string}`;
  targetHfWad: bigint;
  requiredRepay: bigint;
  legs: RescueLeg[];
};
```

---

## 6) Core Logic: Detection and Planning

## Step 1 - Snapshot collection
- Read all adapters on all configured chains:
  - `discoverPositions(user)`
  - `healthFactor(user)`
  - `availableCollateral(user, collateralAsset)`
- Fetch price data according to profile:
  - `CHAINLINK_API_GUARD_V1`: fetch Chainlink API-delivered stream/report data, then verify report before use.
  - quant profiles: use configured price source path plus quant APIs.
- Fetch quant signals from configured HTTP endpoint.
- Reject snapshot as stale if all critical inputs exceed timeout.

## Step 2 - Aggregate risk computation
- Base aggregate HF:
  - weighted by debt share across positions.
- Quant adjustment (profile-dependent):
  - compute risk multiplier from volatility/funding/OI/spread.
  - clamp multiplier to conservative bounded range.
- Trigger condition:
  - `aggregateHF < threshold.aggregateHf` OR `minHF < threshold.emergencyHf`.

## Step 3 - Rescue target sizing
- Determine target endangered position(s), default lowest HF first.
- Compute `targetHf = threshold.aggregateHf * recoveryBuffer`.
- Estimate repay needed to move target toward `targetHf`.

## Step 4 - Source selection (same-chain first)
- Candidate sources ordered by:
  1. same-chain sources before cross-chain sources
  2. higher source HF first (safer source)
  3. larger available collateral
- Per-source cap:
  - `withdrawable = min(availableCollateral, sourceLimitAfterReserve)`
- Build legs until required repay covered or sources exhausted.

## Step 5 - Plan validation
- If no valid legs, emit no-action with reason.
- If tenderly simulation is enabled:
  - simulate execution path
  - in demo mode fail-closed: abort on sim fail

---

## 6.5) CRE Profile Catalog (Per-User Customization)

Each user gets one customized CRE workflow, but for demo onboarding we can offer preset profiles.

## Profile 1 - `CHAINLINK_API_GUARD_V1` (Chainlink Off-Chain Price Path)

Use case:
- Users who want CRE-specific off-chain integration, but not broader third-party quant dependencies.

Data sources:
- Adapter reads:
  - `discoverPositions`, `healthFactor`, `availableCollateral`
- Chainlink API-delivered price stream/report data (off-chain delivery path)
- Chainlink verification path (on-chain verifier/static verification before price is accepted)
- Optional Chainlink L2 Sequencer Uptime Feed (when on L2 lanes)

Logic:
- Fetch latest signed Chainlink price report for each required pair.
- Verify report authenticity/integrity (do not trust raw API payload without verification).
- Build verified effective price and timestamp.
- Compute base aggregate HF from positions using verified prices.
- Compute short-horizon HF deterioration slope from last N workflow snapshots.
- Define tightened effective HF:
  - `effectiveHF = aggregateHF - slopePenalty - stalenessPenalty`
- Trigger early rescue when:
  - `effectiveHF < configuredThreshold`

Why this is tighter than on-chain liquidation HF:
- Uses forward-looking deterioration signal (slope), not only current point-in-time HF.
- Applies precautionary buffer under stale/volatile conditions.
- Uses low-latency off-chain delivery path while retaining verification checks.

Risk control:
- If stream/report fetch fails or verification fails:
  - degrade to conservative fallback (last verified price with stricter penalty), or no-trade mode based on config.

## Profile 2 - `QUANT_FUNDING_OI_V1` (Off-Chain Quant: Funding + OI)

Use case:
- Users who want earlier rescue during leverage build-up and perp stress.

Data sources:
- On-chain:
  - same as `CHAINLINK_API_GUARD_V1` verified price path
- Off-chain quant:
  - Binance USD-M
    - `GET /fapi/v1/premiumIndex` (mark/index + latest funding)
    - `GET /fapi/v1/openInterest`
    - `GET /fapi/v1/fundingRate`
  - Bybit V5
    - `GET /v5/market/open-interest`
    - `GET /v5/market/funding/history`

Logic:
- Build normalized stress score:
  - funding stress (absolute funding and funding acceleration)
  - OI expansion stress (short-window delta and z-score)
  - cross-venue disagreement penalty (Binance vs Bybit divergence)
- Convert stress score to dynamic threshold uplift:
  - `dynamicThreshold = baseThreshold + uplift(stressScore)` (for example +0.02 to +0.15 HF)
- Trigger when:
  - `aggregateHF < dynamicThreshold` OR emergency rule hit.

Why this is tighter:
- Raises rescue threshold before oracle-visible liquidation risk materializes onchain.

## Profile 3 - `QUANT_BASIS_LIQUIDITY_V1` (Off-Chain Quant: Basis + Flow + Liquidity)

Use case:
- Active users who want fastest preemptive rescue under regime shifts.

Data sources:
- On-chain:
  - same as `CHAINLINK_API_GUARD_V1` verified price path
- Off-chain quant:
  - Binance USD-M
    - `GET /fapi/v1/premiumIndex`
    - `GET /futures/data/basis`
    - `GET /futures/data/openInterestHist`
    - `GET /futures/data/takerlongshortRatio`
  - Optional secondary venue confirmation (Bybit):
    - `GET /v5/market/open-interest`
    - `GET /v5/market/funding/history`

Logic:
- Compute regime score from:
  - basis widening / inversion
  - OI growth with one-sided taker flow
  - funding skew and cross-venue dislocation
- Apply two-stage rescue logic:
  1. Pre-emptive stage: smaller same-chain rescue when regime score breaches warning level.
  2. Defensive stage: full rescue plan (including cross-chain legs) when regime score + HF breach both trigger.

Why this is tighter:
- Uses market microstructure stress to front-run rapid deleveraging windows.

## Profile fallback policy
- If quant APIs timeout or fail:
  - degrade to `CHAINLINK_API_GUARD_V1` logic for that execution.
- If quant source disagreement exceeds configured bound:
  - increase caution buffer or require secondary confirmation before large cross-chain legs.

---

## 7) Core Logic: Execution

Execution entry (HTTP primary handler):
1. Check target chain/source chain `rescueInProgress[user]`.
2. If already in progress, skip and emit monitor log.
3. Submit `executeRescue(plan)` on source `RescueExecutor`.
4. Capture tx hash, execution id, and expected message path.
5. Emit workflow output summary.

Post-execution verification:
- Read `RescueLog` entries for execution id.
- Confirm same-chain complete OR cross-chain initiated.
- For cross-chain:
  - wait/reconcile via EVM log handler events.

---

## 8) Cross-Chain Logic (Token + Data via CCIP)

Required pattern:
- Cross-chain legs must use programmable token transfer (`tokenAmounts` + payload `data`).
- Payload includes at minimum:
  - user
  - executionId
  - source protocol key
  - target protocol key
  - debt asset
  - repay amount
  - leg index

Success path:
1. Source executor emits cross-chain initiated log.
2. Destination receiver validates router/source/sender.
3. Destination executor `completeCrossChainLeg(...)` repays target.
4. `RescueLog` records completion.

Failure branches:
- Source fail before send: no state mutation beyond logs.
- Source fail after withdraw: escrow on source chain.
- Destination business failure: escrow on destination chain.
- Workflow must classify and surface branch explicitly.

---

## 9) Trigger Design Details

## HTTP trigger (primary)
- Default mode: bot-driven POST requests.
- Purpose:
  - proactive monitoring and immediate rescue decisioning
  - consistent with external bot architecture
- Security:
  - configured `authorizedKeys` only
  - signed/JWT-triggered gateway calls in deployed mode

## Cron trigger (watchdog)
- Default: every 2-5 minutes for demo.
- Purpose:
  - fallback monitoring if bots are degraded
  - stale data and lock-state watchdog

## EVM log triggers
- Watch `RescueLog`/`RescueExecutor` events:
  - `RescueInitiated`
  - `CrossChainInitiated`
  - `RescueCompleted`
  - `RescueFailed`
  - `Escrowed`
- Purpose:
  - faster reconciliation than pure cron polling
  - recovery action routing (claim/retry candidate detection)

## Manual ops mode (HTTP payload flags)
- Purpose:
  - manual operator force-run
  - replay by execution id
  - dry-run diagnostics

---

## 10) State and Idempotency Strategy

Callbacks are stateless, so idempotency is derived from on-chain state and deterministic ids:
- `executionId = keccak256(user, strategyId, triggerTimeBucket, snapshotHash)`
- Before submitting, check:
  - `rescueInProgress[user] == false`
  - no existing completed `RescueLog` for same execution id

Retry policy:
- transient RPC/API errors: bounded retry with jitter-less backoff suitable for WASM runtime
- deterministic logic errors: fail fast, log, and wait next trigger

---

## 11) Observability and Outputs

Each callback should output structured summary:
- execution id
- trigger type (`cron` | `evm-log` | `http`)
- positions scanned
- aggregate HF and min HF
- decision (`NO_ACTION`, `RESCUE_SAME_CHAIN`, `RESCUE_CROSS_CHAIN`, `ABORT`)
- tx hash/message id when applicable
- failure class when applicable

Recommended on-chain/off-chain correlation keys:
- `executionId`
- CCIP `messageId`
- source tx hash
- destination tx hash

---

## 12) Validation and Test Matrix (CRE Stage)

## Unit tests (workflow logic)
- risk aggregation math
- source ordering and reserve cap logic
- required repay sizing
- plan generation deterministic output for fixed snapshot

## Simulation tests (CRE)
- http no-action path (healthy portfolio)
- http same-chain rescue path
- http multi-source fallback path (>2 positions)
- http cross-chain path success
- cron watchdog no-action path
- source-failure and destination-failure classification paths

## Integration checks
- contract ABI compatibility with adapters/executor/log/escrow
- event decoding for log trigger handlers
- config validation for both Ethereum Sepolia and Base Sepolia

---

## 13) Known Constraints and Design Guardrails

- CRE callbacks are time-limited; keep execution bounded.
- Do not over-parallelize capability calls beyond quotas.
- Keep payload sizes small and deterministic.
- No hidden mutable off-chain state required for correctness.
- Always assume a callback can run again before previous cross-chain flow finalizes; lock checks are mandatory.

---

## 14) Suggested Next Implementation Milestones

1. Replace `cre/rescue-1/main.ts` hello-world with typed config + HTTP-primary skeleton.
2. Add adapter snapshot reads and aggregate HF logic (read-only mode).
3. Add rescue planner (no writes) + deterministic test vectors.
4. Add same-chain executor write path.
5. Add cross-chain execution + reconciliation log handler.
6. Add failure recovery routing and operator-facing outputs.

---

## 15) Primary References

- CRE overview and architecture:
  - [https://docs.chain.link/cre](https://docs.chain.link/cre)
- CRE trigger and callback model:
  - [https://docs.chain.link/cre/capabilities/triggers](https://docs.chain.link/cre/capabilities/triggers)
- CRE EVM log trigger guide:
  - [https://docs.chain.link/cre/guides/workflow/using-triggers/evm-log-trigger-ts](https://docs.chain.link/cre/guides/workflow/using-triggers/evm-log-trigger-ts)
- CRE service quotas:
  - [https://docs.chain.link/cre/service-quotas](https://docs.chain.link/cre/service-quotas)
- CCIP architecture overview:
  - [https://docs.chain.link/ccip/concepts/architecture/overview](https://docs.chain.link/ccip/concepts/architecture/overview)
- CCIP programmable token transfers tutorial:
  - [https://docs.chain.link/ccip/tutorials/evm/programmable-token-transfers](https://docs.chain.link/ccip/tutorials/evm/programmable-token-transfers)
- Chainlink Data Feeds:
  - [https://docs.chain.link/data-feeds](https://docs.chain.link/data-feeds)
- Chainlink L2 Sequencer Uptime Feeds:
  - [https://docs.chain.link/data-feeds/l2-sequencer-feeds](https://docs.chain.link/data-feeds/l2-sequencer-feeds)
- Binance USD-M Futures market data endpoints:
  - [https://developers.binance.com/docs/derivatives/usds-margined-futures/market-data/rest-api](https://developers.binance.com/docs/derivatives/usds-margined-futures/market-data/rest-api)
  - [https://developers.binance.com/docs/derivatives/usds-margined-futures/market-data/rest-api/Open-Interest](https://developers.binance.com/docs/derivatives/usds-margined-futures/market-data/rest-api/Open-Interest)
  - [https://developers.binance.com/docs/derivatives/usds-margined-futures/market-data/rest-api/Mark-Price](https://developers.binance.com/docs/derivatives/usds-margined-futures/market-data/rest-api/Mark-Price)
  - [https://developers.binance.com/docs/derivatives/usds-margined-futures/market-data/rest-api/Get-Funding-Rate-History](https://developers.binance.com/docs/derivatives/usds-margined-futures/market-data/rest-api/Get-Funding-Rate-History)
  - [https://developers.binance.com/docs/derivatives/usds-margined-futures/market-data/rest-api/Basis](https://developers.binance.com/docs/derivatives/usds-margined-futures/market-data/rest-api/Basis)
  - [https://developers.binance.com/docs/derivatives/usds-margined-futures/market-data/rest-api/Open-Interest-Statistics](https://developers.binance.com/docs/derivatives/usds-margined-futures/market-data/rest-api/Open-Interest-Statistics)
  - [https://developers.binance.com/docs/derivatives/usds-margined-futures/market-data/rest-api/Taker-BuySell-Volume](https://developers.binance.com/docs/derivatives/usds-margined-futures/market-data/rest-api/Taker-BuySell-Volume)
- Bybit V5 market data:
  - [https://bybit-exchange.github.io/docs/v5/market/open-interest](https://bybit-exchange.github.io/docs/v5/market/open-interest)
  - [https://bybit-exchange.github.io/docs/v5/market/history-fund-rate](https://bybit-exchange.github.io/docs/v5/market/history-fund-rate)
