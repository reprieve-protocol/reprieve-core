# Reprieve Protocol Contracts To Implement (Post-Lending)

This list covers the Reprieve protocol layer after demo lending mocks/adapters are in place.

## CCIP Principles (Must Follow)

Based on Chainlink CCIP EVM guidance:
- Get started guide: [Get Started with CCIP (EVM)](https://docs.chain.link/ccip/getting-started/evm)
- Security guidance: [CCIP Best Practices (EVM)](https://docs.chain.link/ccip/concepts/best-practices/evm)

Implementation requirements:
- Use official CCIP router/receiver flow and inherit `CCIPReceiver` on destination-side contracts.
- Cross-chain rescue must use CCIP programmable token transfer (token + data), not data-only messages.
- Enforce router gating on receive path (`onlyRouter` behavior).
- Validate trusted destination chains before `ccipSend`.
- Validate trusted source chains in `ccipReceive`.
- Validate trusted sender contract on `ccipReceive` for Reprieve lanes.
- Keep `extraArgs` mutable (do not hardcode permanently).
- Quote fees via `getFee` before send, verify LINK/native fee balance, then approve/pay router.
- Make destination `gasLimit` configurable and backed by tests/estimation.
- Treat `allowOutOfOrderExecution` as lane-dependent config; default for Reprieve should be compatible with lanes requiring out-of-order execution.
- Decouple message reception from heavy business logic; keep receive path minimal and resilient.

## A) Required Core Contracts (MVP Demo)

### 1) `RescueExecutor.sol`
Purpose:
- Main execution contract for rescue actions.
- Executes same-chain-first withdraw + target action via adapters, where target action is mode-based (`TOP_UP` or `REPAY`).
- Initiates CCIP escalation when same-chain source is insufficient.
- Enforces cross-chain lock `rescueInProgress[user]`.

Key functions:
- `executeRescue(RescuePlan calldata plan)`
- `executeSameChainLeg(...)`
- `initiateCrossChainLeg(...)`
- `completeCrossChainLeg(...)` (can be receiver-triggered flow)
- `quoteCcipFee(...)`
- `setCcipExtraArgs(...)`
- `setAuthorizedWorkflow(address workflow, bool allowed)`

Key state:
- `mapping(address => bool) authorizedWorkflow`
- `mapping(address => bool) rescueInProgress`

---

### 2) `RescueLog.sol`
Purpose:
- Immutable on-chain audit trail for every rescue attempt/action.

Key functions:
- `logRescueInitiated(...)`
- `logRescueStep(...)`
- `logRescueCompleted(...)`
- `logRescueFailed(...)`

Key outputs:
- Event stream with protocol, amount, source/target chain, gas/cost metadata, timestamp, workflow execution reference.

---

### 3) `RescueEscrow.sol`
Purpose:
- Holds funds on source chain when CCIP transfer fails.
- Supports user claim or protocol retry path.

Key functions:
- `depositFailedTransfer(...)`
- `claimEscrow(bytes32 escrowId)`
- `retryTransfer(bytes32 escrowId, ...)`

Key state:
- `EscrowRecord` with owner, asset, amount, sourceChain, targetChain, status, retryCount.

---

### 4) `CCIPReceiver.sol`
Purpose:
- Destination-chain CCIP receive handler for rescue payloads/funds.
- Calls executor completion path and unlocks user rescue lock.

Key functions:
- `ccipReceive(...)` / router callback entrypoint
- `_ccipReceive(...)` (internal override)
- `setExecutor(address)`
- `setRouter(address)`
- `setAllowedSourceChain(uint64 selector, bool allowed)`
- `setAllowedSender(uint64 selector, address sender, bool allowed)`

---

### 5) `HealthMonitor.sol` (Minimal, CRE-aligned)
Purpose:
- On-chain checkpoint/event surface for risk snapshots from CRE workflow.
- Keeps monitor/proof surface aligned with spec without duplicating CRE computation logic.

Key functions:
- `recordHealthSnapshot(address user, uint256 aggregateHf, uint256 timestamp, bytes32 execId)`
- `emitUrgentRescue(address user, uint256 prevHf, uint256 newHf)`

Notes:
- No heavy on-chain risk computation required for MVP; CRE is source of truth for trigger logic.

---

## B) Required Supporting Contracts

### 6) `AdapterRegistry.sol`
Purpose:
- Registry for protocol-style adapter addresses used by executor.
- Enables upgrade/replacement of adapter endpoints without redeploying executor.

Key functions:
- `setAdapter(bytes32 protocolId, address adapter)`
- `getAdapter(bytes32 protocolId) returns (address)`
- `setSupportedProtocol(bytes32 protocolId, bool supported)`

---

### 7) `ReprieveTypes.sol` (library/structs)
Purpose:
- Shared structs/enums used across executor, log, escrow, receiver.

Expected types:
- `RescuePlan`
- `RescueStep`
- `RescueMode` (`TOP_UP`, `REPAY`)
- `RescueStatus`
- `EscrowStatus`

---

### 8) `ReprieveErrors.sol` (custom errors)
Purpose:
- Centralized custom errors for gas-efficient revert reasons.

Examples:
- `UnauthorizedWorkflow()`
- `RescueAlreadyInProgress(address user)`
- `BudgetExceeded()`
- `InvalidAdapter(bytes32 protocolId)`
- `EscrowNotClaimable(bytes32 escrowId)`

---

### 9) `ReprieveEvents.sol` (optional split)
Purpose:
- Common event definitions to keep event schema consistent across contracts.

---

## C) Interfaces (Required)

- `IReprieveAdapter.sol` (already aligned in lending layer)
- `IRescueExecutor.sol`
- `IRescueEscrow.sol`
- `IRescueLog.sol`
- `ICCIPReceiver.sol`
- `IAdapterRegistry.sol`

---

## D) Explicitly Out Of Scope (Do Not Implement)

- `RescueConfig.sol` (config stored in per-user CRE workflow)
- `BudgetGuard.sol` as standalone contract (budget logic remains CRE-side for MVP)
- `PriceWatcher.sol` (price checks performed in CRE via Data Feeds)
- Full production-grade CCIP retry orchestration framework

---

## E) Recommended Build Order

1. `ReprieveTypes.sol`, `ReprieveErrors.sol`, interfaces
2. `AdapterRegistry.sol`
3. `RescueLog.sol`
4. `RescueEscrow.sol`
5. `RescueExecutor.sol` (same-chain first)
6. `CCIPReceiver.sol` (cross-chain completion path)
7. `HealthMonitor.sol` (minimal checkpoint/events)

---

## F) Minimum Demo Acceptance Per Contract Set

- Same-chain rescue can execute via `RescueExecutor` + adapters.
- Cross-chain attempt can be initiated and either completed or escrowed.
- `rescueInProgress[user]` prevents concurrent rescue races.
- Every major action emits auditable events via `RescueLog`.
- Escrowed funds are claimable/retriable via `RescueEscrow`.
- CCIP receive path rejects untrusted router/source/sender.
- CCIP send path uses configurable `extraArgs` and fee quote checks.

---

## G) Lending Integration Map (Current Repo Reference)

This section maps Reprieve contracts to currently implemented lending contracts in `contracts/src`.

### Implemented Contracts (Source of Truth)
- Aave-like market: `MockAavePool.sol`
- Compound-like market: `MockCompoundMarket.sol`
- Morpho-like market: `MockMorphoMarket.sol`
- Shared engine: `BaseLendingEngine.sol`
- Adapters: `AaveLikeAdapter.sol`, `CompoundLikeAdapter.sol`, `MorphoLikeAdapter.sol`
- Shared adapter interface: `IReprieveAdapter.sol`

### Reprieve -> Adapter -> Lending Calls
- Position discovery:
  - Reprieve reads `discoverPositions(user)` and `healthFactor(user)` from each adapter.
  - Adapter reads `getUserPosition(user)` and `getHealthFactor(user)` from market contracts.
- Same-chain withdraw leg:
  - Reprieve executor calls `withdrawForRescue(user, collateralAsset, amount, to)` on source adapter.
  - Adapter calls market-specific withdraw/redeem path.
- Same-chain top-up leg:
  - Reprieve executor calls `supplyForRescue(user, collateralAsset, amount)` on target adapter.
  - Adapter pulls collateral token from executor and supplies collateral on-behalf-of the user in target market.
- Same-chain repay leg:
  - Reprieve executor calls `repayForRescue(user, debtAsset, amount)` on target adapter.
  - Adapter pulls debt token from executor and repays debt on-behalf-of the user in target market.

### Compatibility Requirements To Lock
- For reliable rescue integration, each market must expose a callable withdraw path compatible with its adapter:
  - Aave-like: provide/keep a `withdraw(address asset, uint256 amount, address to)`-compatible path.
  - Compound-like: `redeem(...)` or fallback withdraw path already used by adapter.
  - Morpho-like: provide/keep `withdrawCollateral(...)` or a generic withdraw fallback.
- Adapter `withdrawForRescue` must enforce delegated authority semantics for `user` (who owns the collateral position), not only `msg.sender`.
- All rescue-critical methods should emit deterministic events for `RescueLog` correlation.

---

## H) Execution Mode Model (Plan-Level Constraint)

`RescuePlan` must carry a single mode:
- `TOP_UP`: rescue by adding collateral to the target position.
- `REPAY`: rescue by reducing target debt exposure.

Hard rule (required):
- One `executeRescue` call uses exactly one mode for all its steps.
- Mixed mode steps inside the same execution are invalid and must revert.

Field interpretation by mode:
- `TOP_UP`
  - Uses `collateralAsset` + `collateralAmount` for target action.
  - Calls `supplyForRescue`.
  - `debtAsset/debtAmount` are ignored legacy fields.
- `REPAY`
  - Uses `debtAsset` + `debtAmount` for target action.
  - Calls `repayForRescue`.
  - `collateralAsset/collateralAmount` remain source-withdraw fields.

Token-conversion boundary (important for demo correctness):
- No DEX/swap inside executor.
- If withdrawn source asset cannot satisfy target action asset, step must fail and follow existing escrow/failure handling.
- Cross-chain relies on configured token mapping (CCIP mock/prod lane). Mapping mismatch must fail deterministically and route to recoverable path.

Hedging scenario mapping (your example):
- `REPAY` mode.
- WETH-dump branch:
  - withdraw USDC from source leg that has lend-USDC,
  - repay USDC debt on target leg that has borrow-USDC.
- WETH-pump branch:
  - withdraw WETH from source leg that has lend-WETH,
  - repay WETH debt on target leg that has borrow-WETH.

---

## I) Scenario Design: Reprieve <-> Lending Interactions

### Scenario 1: Same-Chain Rescue (Single Source -> Single Target)

Preconditions:
- User has at least one risky target position and one healthy source position on the same chain.
- Executor is authorized by CRE workflow.
- `rescueInProgress[user] == false`.

Flow:
1. CRE submits rescue plan to `RescueExecutor.executeRescue`.
2. Executor sets `rescueInProgress[user] = true`.
3. Executor selects source and target adapters from `AdapterRegistry`.
4. Executor calls source `availableCollateral(user, collateralAsset)` and caps amount by reserve rule (max 80% withdraw).
5. Executor calls source `withdrawForRescue(user, collateralAsset, amount, address(this))`.
6. Executor dispatches target action by plan mode:
  - `TOP_UP`: `supplyForRescue(user, collateralAsset, collateralAmount)`
  - `REPAY`: `repayForRescue(user, debtAsset, debtAmount)`
7. Executor records each leg in `RescueLog`.
8. Executor clears lock and emits completion.

Success criteria:
- `TOP_UP`: target collateral increases and HF improves.
- `REPAY`: target debt decreases and HF improves.
- Logs include source protocol, target protocol, amount, user, and execution id.

### Scenario 2: Same-Chain Rescue Involving More Than 2 Positions

Preconditions:
- User has one endangered target and multiple candidate sources (>=2), possibly across Aave-like/Compound-like/Morpho-like positions on the same chain.

Flow:
1. CRE provides ordered priority queue (highest-HF source first).
2. Executor iterates sources:
  - reads `availableCollateral`.
  - withdraws partial/full amount from source.
  - executes target action based on plan mode (`TOP_UP` or `REPAY`).
3. If source #1 is insufficient, executor falls through to #2, then #3, until target top-up requirement is met or queue exhausted.
4. Executor writes per-leg logs with `stepIndex`.
5. Executor finalizes with success (fully recovered) or partial-success (improved but below target buffer).

Success criteria:
- At least one fallback leg is demonstrably executable.
- Per-leg accounting is auditable (sum withdrawn == sum routed/remaining).
- No concurrent rescue overlap for the same user.

### Scenario 3: Cross-Chain Rescue (Happy Path)

Preconditions:
- No sufficient same-chain source on destination chain.
- Source chain has withdrawable collateral.
- Trusted CCIP lane configured (router/source/destination/sender).

Flow:
1. Source `RescueExecutor` locks `rescueInProgress[user]`.
2. Source executor withdraws from source adapter into executor custody.
3. Source executor builds `EVM2AnyMessage` with:
  - `tokenAmounts` carrying action token amount (mode-dependent)
  - `data` carrying routing payload including mode + target asset/amount + execution context
  - lane-configured `extraArgs`
  Then quotes fee with `getFee`.
4. Source executor sends message via router and logs `CrossChainInitiated`.
5. Destination `CCIPReceiver` validates router + source chain + sender.
6. Destination receiver calls destination executor `completeCrossChainLeg(...)`.
7. Destination executor approves target adapter and dispatches by mode:
  - `TOP_UP`: `supplyForRescue(...)`
  - `REPAY`: `repayForRescue(...)`
8. Destination executor logs completion and clears lock state for user on destination-side rescue state.
9. Source-side workflow records completed status (via event indexing / off-chain workflow step).

Success criteria:
- `TOP_UP`: destination collateral increased on target position.
- `REPAY`: destination debt reduced on target position.
- CCIP message id linked in `RescueLog`.
- User lock is not left stuck.
- Both token transfer and payload decoding are validated in tests.

### Scenario 4: Cross-Chain Failure On Source Chain

Definition:
- Failure before successful CCIP dispatch (for example withdraw fails, fee quote/payment fails, router send reverts).

Flow:
1. Executor attempts source withdraw and/or fee preparation.
2. If failure occurs before any asset movement:
  - revert rescue step.
  - clear `rescueInProgress[user]`.
  - log `CrossChainSourceFailed`.
3. If collateral was already withdrawn but CCIP send fails:
  - deposit funds into `RescueEscrow` on source chain.
  - mark escrow record claimable/retriable.
  - clear `rescueInProgress[user]`.
  - log failure + escrow id.

Success criteria:
- No silent fund loss.
- No permanent lock.
- Clear recovery path via claim or retry.

### Scenario 5: Cross-Chain Failure On Destination Chain

Definition:
- CCIP message arrives, but destination business action fails (for example target adapter top-up/repay revert).

Flow:
1. Destination receiver validates router/source/sender.
2. Receiver invokes destination completion with `try/catch` style handling.
3. If completion fails:
  - move received funds to destination `RescueEscrow` (or hold in receiver escrow mode).
  - emit `CrossChainDestinationFailed` with reason + escrow id.
  - mark user state as recoverable/retriable, avoiding permanent lock.
4. Retry path:
  - protocol retries completion with corrected parameters, or user claims escrowed funds.

Success criteria:
- Message receipt is auditable even when business logic fails.
- Funds remain recoverable.
- Retry/claim operations are explicit and testable.

---

## J) Validation Checklist For Interaction Scenarios

- [ ] Same-chain TOP_UP single-source rescue test: withdraw then collateral top-up improves HF.
- [ ] Same-chain REPAY single-source rescue test: withdraw compatible asset then debt repay improves HF.
- [ ] Same-chain multi-source test: at least 3 positions, fallback from source #1 to #2 works in one selected mode.
- [ ] Cross-chain TOP_UP success test: message id emitted, destination top-up succeeds, lock cleared.
- [ ] Cross-chain REPAY success test: message id emitted, destination repay succeeds, lock cleared.
- [ ] Cross-chain source-fail test: failure before send does not trap funds or lock.
- [ ] Cross-chain source-fail-after-withdraw test: escrow deposit occurs and is claimable/retriable.
- [ ] Cross-chain destination-fail test: receiver path records failure and funds are recoverable.
- [ ] Mixed-mode-in-one-plan test: execution reverts.
- [ ] Event correlation test: every scenario produces `RescueLog` entries with execution id and step index.
