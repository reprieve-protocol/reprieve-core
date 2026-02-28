# CCIP Concepts + Smart Contract Dev Guide (EVM)

Audience:
- Smart contract dev agent implementing CCIP-enabled contracts in this repo.

Scope:
- EVM-only guidance.
- Focus on sender/receiver contracts, safety controls, gas/fee handling, and failure recovery.
- Aligned for Reprieve-style cross-chain rescue execution.
- Primary coding baseline: CCIP tutorial "Transfer Tokens with Data" (programmable token transfers).

Last verified against docs:
- February 28, 2026

---

## 1) Core CCIP Concepts You Must Internalize

### What CCIP does
- CCIP supports:
  - token transfers
  - arbitrary data messaging
  - programmable token transfers (tokens + data)

### Two-layer architecture
- Offchain:
  - Role DON runs two OCR plugins:
    - Commit OCR plugin
    - Executing OCR plugin
- Onchain:
  - Router: single immutable user-facing interface per chain.
  - OnRamp: source-side internal processor.
  - OffRamp: destination-side internal processor.
  - FeeQuoter: fee estimation and pricing.
  - Token Admin Registry + Token Pools: lock/burn and release/mint routing.
  - RMN: curse checks used by onchain components.

### Message lifecycle (EVM mental model)
1. Sender calls Router `ccipSend`.
2. OnRamp validates and emits sent event.
3. Commit OCR process commits merkle roots (and price reports).
4. OffRamp accepts commit report.
5. Executing OCR process submits execution report.
6. OffRamp verifies proofs, processes tokens/data, sets execution status.
7. Router/receiver flow delivers to destination receiver if data is present.

Inferred design implication:
- Your app contract should only integrate with Router + receiver interface, not OnRamp/OffRamp directly.

---

## 1.5) Primary Reference Pattern (Mandatory)

Use this tutorial as the default implementation template:
- https://docs.chain.link/ccip/tutorials/evm/programmable-token-transfers

And this defensive extension for failure recovery:
- https://docs.chain.link/ccip/tutorials/evm/programmable-token-transfers-defensive

What to copy as baseline behavior:
- Build messages with `Client.EVM2AnyMessage`.
- Include both:
  - `tokenAmounts` for transferred value
  - `data` for routing/business payload
- Support both fee modes:
  - LINK fee token path
  - native gas fee path
- Receiver implements `_ccipReceive(Client.Any2EVMMessage memory)`.
- Receiver enforces router + source chain + sender allowlist checks.

---

## 2) Must-Follow Security Rules (Non-Negotiable)

### Validation gates
- Before send:
  - allowlist/validate destination chain selectors.
- On receive:
  - validate source chain selector.
  - validate decoded sender allowlist (when app-specific trust is required).
- enforce router caller gate (`onlyRouter` via `CCIPReceiver` base or equivalent).
- keep sender and receiver concerns separated at contract boundary (or clearly separated modules) to reduce privileged surface.

### `extraArgs` policy
- Do not hardcode permanently.
- Keep mutable (storage or input param) for upgrade compatibility.

### `gasLimit` policy
- `gasLimit` is main fee driver for destination `ccipReceive`.
- Unused gas is not refunded.
- If receiver is EOA-only token transfer, set gas limit to `0`.

### `allowOutOfOrderExecution`
- Lane-dependent feature (Optional vs Required).
- Check lane capability in CCIP Directory before setting behavior.
- Docs indicate in-order enforcement path (`allowOutOfOrderExecution=false`) is being deprecated in early 2026.

### Router/OffRamp/OnRamp address handling
- Use Router as integration anchor.
- Do not hardcode OnRamp/OffRamp addresses; docs warn they can change with updates.

---

## 3) Sender Contract Implementation Pattern

Mirror the tutorial’s two send functions (`sendMessagePayLINK`, `sendMessagePayNative`) with Reprieve payloads.

Use this flow in sender entrypoints:
1. Build `Client.EVM2AnyMessage`:
  - `receiver` as bytes-encoded destination address.
  - `data` as encoded payload (for Reprieve: user, executionId, protocol key, debt asset, repay amount, step index).
  - `tokenAmounts` with the collateral token + amount (for cross-chain rescue).
  - `extraArgs` built from mutable config.
  - `feeToken` (LINK, native, or supported fee token).
2. Call Router `getFee`.
3. Validate fee affordability.
4. Approve token transfer amount for router.
5. If paying in LINK/ERC20 fee token, approve fee token for router.
6. If paying in native, pass `msg.value = fees`.
7. Call Router `ccipSend`.
8. Emit app-level event with message ID and business context.

Recommended sender state:
- `mapping(uint64 => bool) trustedDestinationChains`
- mutable `extraArgs` config (gas limit + out-of-order flag)
- optional per-lane overrides

---

## 4) Receiver Contract Implementation Pattern

Base structure:
- Inherit Chainlink `CCIPReceiver`.
- Implement `_ccipReceive(Client.Any2EVMMessage memory msg)`.

Defensive production pattern (recommended):
- `ccipReceive` entry should never unexpectedly brick flows.
- Validate source chain + sender allowlists before processing.
- Decouple message reception from heavy business logic:
  - route into internal/external `processMessage(...)` with `try/catch`.
  - store failed message data.
  - emit failure event.
  - provide explicit admin/operator retry function.

Tutorial-aligned parsing requirements:
- Read `messageId`.
- Decode `sender` from bytes to address for allowlist checks.
- Decode `data` bytes to your payload struct.
- Read received token from `destTokenAmounts` (tutorial assumes first entry; production should validate length and token expectations).

Inferred recommendation for Reprieve:
- `ReprieveCCIPReceiver` should only validate + dispatch.
- Business logic should live in `RescueExecutor.completeCrossChainLeg`.

---

## 5) Fee, Gas, and Limits You Must Respect

### Fee model
- `getFee` returns estimated fee for the exact message payload and options.
- Fee varies with:
  - destination lane
  - gas limit
  - message size/data
  - token transfer composition
  - fee token

### Global service limits (EVM docs)
- Max message `data` payload: 30 KB
- Message execution gas limit: 3,000,000
- Max distinct tokens per tx: 1
- Token pool execution gas budget: 90,000 (for required pool path steps)
- Some network-specific exceptions apply (check docs per network).

### Gas estimation workflow
1. Estimate locally (Foundry/Hardhat/Tenderly/web3 provider).
2. Validate on testnet with realistic payload sizes.
3. Add safety buffer.
4. Monitor live failures and tune by lane.

---

## 6) Failure Modes and Recovery Strategy

### Common failure triggers
- Gas limit too low on destination `ccipReceive`.
- Receiver logic revert/unhandled exception.
- Token pool execution too heavy (token pool gas path issues).

### Manual execution (critical fallback)
- Failed eligible messages can be manually executed on destination.
- CCIP Explorer supports manual execution with gas override.
- Merkle proof is submitted and verified against OffRamp committed root.
- Any EOA can manually execute eligible messages if they fund gas.

App design requirements:
- Keep message IDs in app events/state for operator tooling.
- Support replay/retry logic in receiver/executor flows.
- Avoid permanent locks when destination processing fails.

Tutorial-derived defensive requirement:
- Implement failed-message tracking and explicit retry/recovery entrypoint (similar to `retryFailedMessage` pattern in defensive tutorial).

---

## 7) CCIP Directory Usage Requirements

Before any deployment or send:
- Read CCIP Directory for each target chain/lane and fetch:
  - Router address
  - Chain selector
  - RMN address
  - Token admin registry address
  - Supported fee tokens
  - Lane availability/status
  - Lane version

Do not assume two lanes have identical capabilities.

Inferred operational rule:
- Store directory-derived config in per-chain config files and validate at startup/deploy time.

---

## 8) Reprieve-Specific Mapping (No CRE Phase)

For this repo’s current architecture:
- `RescueExecutor`:
  - same-chain rescue first
  - cross-chain send via Router after fee quote
  - keeps per-user lock state
- `ReprieveCCIPReceiver`:
  - validates router/source/sender
  - forwards to `RescueExecutor.completeCrossChainLeg`
- `RescueEscrow`:
  - stores recoverable funds on source/destination failure branches
- `RescueLog`:
  - app-level auditable lifecycle events linked to CCIP message ID

Required receive-path behavior:
- validate
- attempt complete
- on failure: escrow + failure event + recoverability path
- never leave ambiguous terminal state

---

## 9) Contract Dev Checklist (Agent Execution)

### Build checklist
- [ ] Use `CCIPReceiver` base on destination.
- [ ] Validate destination chain before send.
- [ ] Validate source chain + sender on receive.
- [ ] Keep `extraArgs` mutable.
- [ ] Use `getFee` + affordability checks before `ccipSend`.
- [ ] Build programmable transfer messages with both `tokenAmounts` and encoded `data`.
- [ ] Emit message ID in app-level events.
- [ ] Implement failure storage + retry/recovery path.
- [ ] Integrate manual-execution-aware runbook.

### Test checklist
- [ ] Happy-path send/receive.
- [ ] Invalid destination selector reject.
- [ ] Invalid router caller reject.
- [ ] Invalid source selector reject.
- [ ] Invalid sender reject.
- [ ] Low gas -> failure path -> manual/retry path.
- [ ] Destination logic revert -> escrow/recovery path.
- [ ] Message replay/double-process protection.

### Ops checklist
- [ ] Directory config refresh before each deploy.
- [ ] Lane capability check for out-of-order setting.
- [ ] Service-limit checks on payload size and gas.
- [ ] Monitoring for failed/ready-for-manual messages.

---

## 10) Sources

- CCIP Architecture Overview:
  - https://docs.chain.link/ccip/concepts/architecture/overview
- Onchain Architecture Components (EVM):
  - https://docs.chain.link/ccip/concepts/architecture/onchain/evm/components
- Offchain Architecture Overview:
  - https://docs.chain.link/ccip/concepts/architecture/offchain/overview
- Get Started with CCIP (EVM):
  - https://docs.chain.link/ccip/getting-started/evm
- CCIP Best Practices (EVM):
  - https://docs.chain.link/ccip/concepts/best-practices/evm
- Transfer Tokens with Data (primary tutorial):
  - https://docs.chain.link/ccip/tutorials/evm/programmable-token-transfers
- Defensive example (transfer tokens with data):
  - https://docs.chain.link/ccip/tutorials/evm/programmable-token-transfers-defensive
- Gas limit optimization tutorial:
  - https://docs.chain.link/ccip/tutorials/evm/ccipreceive-gaslimit
- Manual execution concept:
  - https://docs.chain.link/ccip/concepts/manual-execution
- CCIP Service Limits (EVM):
  - https://docs.chain.link/ccip/service-limits/evm
- CCIP Directory (testnet):
  - https://docs.chain.link/ccip/directory/testnet
