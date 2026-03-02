# Mock CCIP-Compatible Token + Router/Receiver Plan

This plan defines what to change from the current repo state to support a **demo-owned CCIP-like bridge flow** using **burn on source + mint on destination** with programmable token transfers (token + data), without relying on limited Chainlink testnet CCIP infra.

## Implementation Notes (Current Repo)

- `MockERC20` now includes bridge burner/minter roles and `bridgeBurn`/`bridgeMint`.
- `MockCCIPRouter` now enforces lane + token mapping config, burns on `ccipSend`, mints on delivery, and tracks message status (`Pending/Delivered/Failed`) with retry support.
- `RescueExecutor.completeCrossChainLeg` now pulls bridged tokens from caller (`CCIPReceiver`) before repaying, so destination repayment no longer requires executor prefunding.
- Cross-chain integration path is wired for **source-token -> destination-token mapping** (e.g., source collateral token can map to destination debt token for repay).

## Status Snapshot (March 1, 2026)

- Slide 1 (Token upgrade): **Done** (implemented by extending `MockERC20` instead of creating `MockCCIPToken.sol`).
- Slide 2 (Router v2 behavior): **Done** (`MockCCIPRouter` evolved with burn/mint + lane/token mapping + message status + retry).
- Slide 3 (Receiver integration): **Done** (`CCIPReceiver` wired with updated router flow).
- Slide 4 (Asset semantics): **Done** (resolved via source-token -> destination-token mapping; cross-chain repay no longer depends on destination prefunding).
- Slide 5 (Deploy/config/scripts): **Partial** (wiring + ops/runbook + `mock-router-deploy` done; router/token mapping artifact standardization still open).
- Slide 6 (tests): **Partial** (new unit/integration coverage added and targeted suites pass; full-suite pass not yet re-run).
- Slide 7 (CRE implications): **Design complete** (no additional code required in this phase).
- Slide 8 (rollout): **In progress** (core contract/test milestones done; remaining deployment workflow polish pending).

## 0) Current State Analysis (What Exists vs What Is Missing)

### Existed At Plan Creation
- `MockERC20` supports admin mint/burn (`minter`) and regular ERC20 behavior.
- `MockCCIPRouter` supports `ccipSend`, stores message, and `deliverMessage`.
- `RescueExecutor` builds token+data message and calls router.
- `CCIPReceiver` validates router/source/sender and dispatches rescue completion.
- Cross-chain tests are passing with mock infra.

### Initial Gaps To Address
- `MockERC20` is **not bridge-role aware** (no dedicated burner/minter roles for cross-chain routing).
- `MockCCIPRouter` uses **lock/unlock transfer** simulation, not burn/mint.
- No per-lane token mapping for source token -> destination token.
- No explicit message lifecycle model (queued/delivered/failed/retried) in router state.
- Critical rescue logic mismatch:
  - cross-chain token transfer sends `collateralAsset`
  - destination repay uses `debtAsset`
  - current tests succeed because destination executor is pre-funded with debt token.
  - This must be resolved for deterministic bridge-driven rescue.

### Gap Resolution Status
- Resolved by adding bridge roles to `MockERC20` and bridge ops (`bridgeBurn`/`bridgeMint`).
- Resolved by evolving `MockCCIPRouter` from lock/unlock simulation to burn/mint programmable transfer flow.
- Resolved by adding per-lane token mapping and lane enablement checks in router.
- Resolved by adding router message lifecycle status (`Pending`, `Delivered`, `Failed`) and retry path.
- Resolved by changing cross-chain completion funding path so destination repay uses bridged token delivered into `CCIPReceiver`.

---

## Slide 1 - Token Contract Upgrade (CCIP-Compatible Mock)

### Build Scope
- Add a new token contract (recommended: `MockCCIPToken.sol`) instead of mutating `MockERC20` directly.

### Required Features
- ERC20 + configurable decimals.
- Role model (AccessControl or equivalent):
  - `DEFAULT_ADMIN_ROLE`
  - `BRIDGE_BURNER_ROLE`
  - `BRIDGE_MINTER_ROLE`
- Bridge methods:
  - `bridgeBurn(address from, uint256 amount)`
  - `bridgeMint(address to, uint256 amount)`
- Optional compatibility helpers:
  - `bridgeBurnFrom(address from, uint256 amount)` (allowance-based UX)
  - role grant/revoke events

### Acceptance Criteria
- Only authorized bridge burner can burn for cross-chain send.
- Only authorized bridge minter can mint for cross-chain delivery.
- Admin can rotate router/bridge roles safely.

### Validation Checklist
- [x] Unauthorized burn/mint reverts.
- [x] Authorized burn decreases total supply on source.
- [x] Authorized mint increases total supply on destination.
- [x] Role rotation works and old role loses privileges.

---

## Slide 2 - Router v2 (Burn/Mint Programmable Transfer)

### Build Scope
- Add `MockCCIPRouterV2.sol` (or evolve `MockCCIPRouter` in a backward-compatible way).

### Required Features
- `ccipSend`:
  - validates supported lane/token
  - burns source token via `bridgeBurn` (instead of custody transfer)
  - stores message metadata + payload + token amount
- `deliverMessage`:
  - resolves destination token mapping
  - mints destination token via `bridgeMint`
  - calls destination receiver with token+data payload
- Router config:
  - `setLane(uint64 source, uint64 dest, bool enabled)`
  - `setTokenMapping(uint64 destChain, address sourceToken, address destToken)`
  - `setReceiver(uint64 destChain, address receiver)` (optional convenience)
- Message state machine:
  - `Pending -> Delivered`
  - `Pending -> Failed` (with reason)
  - retry entrypoint for failed deliveries

### Acceptance Criteria
- Router no longer depends on pre-funded liquidity custody.
- Source supply burns and destination supply mints are auditable by message ID.
- Token+data delivery remains receiver-compatible.

### Validation Checklist
- [x] Send burns exactly `tokenAmount`.
- [x] Deliver mints exactly `tokenAmount`.
- [x] Unsupported lane/token mapping reverts.
- [x] Duplicate delivery is blocked.
- [x] Failed delivery is retryable with explicit status.

---

## Slide 3 - Receiver Integration (Custom Router + Existing Reprieve Receiver)

### Build Scope
- Keep `CCIPReceiver.sol` as business receiver, wire it to new router.
- Add minimal compatibility adjustments only if payload shape changes.

### Required Features
- `onlyRouter` path must accept custom router address.
- Preserve source-chain and sender allowlists.
- Preserve failure escrow + retry logic.

### Acceptance Criteria
- Existing receiver security gates remain intact with custom router.
- Delivery from non-router / untrusted sender still fails.

### Validation Checklist
- [x] Router gate test passes with new router.
- [x] Allowed source/sender checks pass.
- [x] Failure path still escrows and records failed message.

---

## Slide 4 - Cross-Chain Rescue Asset Semantics (Must Resolve Before Final Wiring)

### Problem
- Current flow bridges collateral token but repays destination debt token.
- Without swap/credit conversion, bridged collateral cannot directly repay debt.

### Decision Required (Pick One)
- Option A (recommended for demo determinism):
  - Bridge **debt token** for cross-chain repay legs.
  - Source leg must obtain debt token amount (via predefined funding or protocol-specific logic).
- Option B:
  - Keep bridging collateral, add conversion module (mock swapper) on destination before repay.
- Option C:
  - Restrict cross-chain rescue scenario to markets where repay asset equals bridged asset.

### Acceptance Criteria
- Cross-chain leg succeeds using assets received from router bridge flow, not pre-funded destination float.

### Validation Checklist
- [x] Cross-chain success test no longer relies on manual debt pre-funding.
- [x] Payload asset and transferred/minted token are consistent with repay path.

---

## Slide 5 - Deploy/Config/Scripts Update

### Build Scope
- Extend deployment scripts to support bridge-token mode.
- Preserve one-command operator UX (`scripts/ops.sh`).

### Required Changes
- Lending deploy:
  - optional deploy of `MockCCIPToken` pair per chain
  - optional reuse of existing token addresses from env
- Router deploy/wire scripts:
  - deploy router v2
  - configure lane + token mappings + receiver mappings
  - grant burner/minter roles to router (or bridge executor) on both chains
- Reprieve stack deploy:
  - wire custom router address by chain env

### Acceptance Criteria
- Human operator can run one command per chain with `.env` values.
- Bridge role wiring is deterministic and verifiable.

### Validation Checklist
- [x] `ops.sh` supports router v2 deployment/wiring workflow.
- [ ] Role grants visible in logs/artifacts.
- [ ] Config artifacts include token/router/receiver mappings.

---

## Slide 6 - Test Matrix (Unit + Integration + Scenario)

### Unit Tests
- `MockCCIPToken` roles and bridge mint/burn behavior.
- Router v2 lane/token mapping, send/deliver state transitions.

### Integration Tests
- End-to-end programmable transfer:
  - send burns source
  - deliver mints destination
  - receiver executes destination action

### Rescue Scenario Tests
- Same-chain unchanged baseline still passes.
- Cross-chain success with burn/mint tokens and no manual debt float.
- Source failure / destination failure / retry / escrow recovery still pass.

### Acceptance Criteria
- Full `forge test --summary` passes with new bridge stack.

### Validation Checklist
- [ ] All existing suites still green or intentionally migrated.
- [x] New burn/mint and mapping tests added.
- [x] Cross-chain scenario assertions include supply changes on both chains.

### Current Validation Runs
- `forge test --match-contract MockCCIPRouterTest -vv`: passed (5/5)
- `forge test --match-contract PrimitivesTest -vv`: passed (39/39)
- `forge test --match-contract CrossChainIntegrationTest -vv`: passed (3/3)
- `forge test --match-contract RescueExecutorCrossChainTest -vv`: passed (11/11)
- `forge test --match-contract CCIPReceiverTest -vv`: passed (23/23)
- `forge build --skip test`: passed

---

## Slide 7 - CRE Workflow Implications

### Recommended CRE Interaction Model
- CRE triggers router/executor actions, not direct token mint/burn calls in normal path.
- Router owns mint/burn responsibilities via token roles.
- CRE can keep emergency/manual ops to invoke retry/recovery scripts.

### Why
- Keeps bridge authority surface centralized.
- Produces cleaner message/audit trail via router message IDs.
- Avoids dual-source-of-truth between CRE and router state.

---

## Slide 8 - Rollout Sequence

1. Implement `MockCCIPToken`.
2. Implement Router v2 burn/mint flow + mappings.
3. Wire existing `CCIPReceiver` to Router v2.
4. Resolve asset semantics choice for cross-chain repay.
5. Update deploy/ops scripts + artifacts.
6. Migrate and extend tests.
7. Run end-to-end demos on Ethereum Sepolia + Base Sepolia.

---

## Out of Scope (For This Plan)
- Production-grade token pool security model equivalent to real Chainlink pools.
- Real CCIP directory/onramp/offramp integration.
- Full DEX pricing/slippage modeling for cross-asset swap route (unless Option B is chosen).
