# Reprieve Backend Design (NestJS + Postgres)

Related specs:
- [reprieve-contracts-design.md](/Users/sniperman/code/reprieve/specs/reprieve-contracts-design.md)
- [reprieve-cre-workflow-design.md](/Users/sniperman/code/reprieve/specs/reprieve-cre-workflow-design.md)
- [mock-ccip-token-router-implementation-plan.md](/Users/sniperman/code/reprieve/specs/mock-ccip-token-router-implementation-plan.md)

---

## 1) Goal

Build a backend service that:
- Reads and syncs user lending positions across supported chains and demo protocols.
- Relays mock CCIP messages after source-chain cross-chain rescue initiation events.
- Indexes rescue lifecycle logs/history and provides query APIs for app UI and operators.

Stack:
- NestJS (TypeScript)
- PostgreSQL

---

## 2) Scope (This Stage)

- Supported chains:
  - Ethereum Sepolia (`11155111`)
  - Base Sepolia (`84532`)
- Position sync:
  - API-triggered sync for `address` across supported chains and demo lending protocols.
  - Cached reads with freshness metadata.
- Relay automation:
  - Listen for source-chain cross-chain initiation event.
  - Trigger equivalent of:
    - `./scripts/ops.sh cross-chain-rescue-relay ethereum-sepolia base-sepolia <message-id>`
- Rescue history indexing:
  - Persist rescue events, statuses, and CCIP message links.
  - Query APIs for list/detail/time-range views.

---

## 3) Constraints and Assumptions

- Demo chain scope is fixed to Sepolia/Base Sepolia.
- Protocol scope is fixed to demo mocks/adapters already deployed in repo configs.
- Position sync is eventual-consistent, not strongly consistent across chains in one block.
- Relay engine in this phase uses existing script tooling (`scripts/ops.sh`) as execution primitive.
- Backend reads addresses from deployment artifacts/config files, with env override support.

---

## 4) Non-goals (This Stage)

- Production-grade cross-chain relayer replacement for Chainlink infra.
- Multi-tenant authz/RBAC and enterprise user management.
- Portfolio optimization/rebalance logic.
- Real mainnet protocol integrations.
- Full CRE orchestration engine inside backend (backend only triggers/observes).

---

## 5) High-Level Architecture

Nest modules:
- `chains` module:
  - chain registry, RPC providers, block cursor state.
- `positions` module:
  - sync orchestration per user/chain/protocol.
  - cache policy and upsert logic.
- `relay` module:
  - source event listener.
  - relay job queue/executor (invokes `ops.sh cross-chain-rescue-relay`).
- `rescue-history` module:
  - index RescueExecutor/RescueLog/CCIPReceiver events.
  - derive lifecycle view.
- `api` module:
  - REST controllers for positions, rescues, relay jobs.
- `persistence` module:
  - Postgres entities/migrations/repositories.

Background workers:
- `event-indexer-worker`:
  - scans chains by block range, parses events, persists/upserts.
- `relay-worker`:
  - picks pending relay jobs, executes script, records result/retries.
- `cache-expiry-worker` (optional):
  - marks stale snapshots for refresh.

---

## 6) Contract/Event Coverage

Source contracts/events to index:
- `RescueExecutor`:
  - `RescueInitiated`
  - `RescueStepCompleted`
  - `RescueCompleted`
  - `RescueFailed`
  - `CrossChainInitiated`
- `RescueLog`:
  - `LogEntryAdded`
- `CCIPReceiver`:
  - `CrossChainCompleted`
  - `CrossChainDestinationFailed`
  - `MessageFailed` (if emitted)
- `RescueEscrow`:
  - `EscrowCreated`

Position read path:
- Read via deployed adapters on each chain:
  - `discoverPositions(user)`
  - `availableCollateral(user, asset)` (optional extra)
  - `healthFactor(user)` (optional extra)

---

## 7) Data Model (Postgres)

`chains`
- `id` (pk)
- `key` (`ethereum-sepolia`, `base-sepolia`)
- `chain_id`
- `rpc_url`
- `is_enabled`

`protocol_adapters`
- `id` (pk)
- `chain_id` (fk -> chains)
- `protocol` (`AAVE`, `COMPOUND`, `MORPHO`)
- `adapter_address`
- `market_address`
- `collateral_asset`
- `debt_asset`
- `is_enabled`

`position_snapshots`
- `id` (pk)
- `user_address`
- `chain_id` (fk)
- `protocol`
- `adapter_address`
- `collateral_asset`
- `debt_asset`
- `collateral_amount_raw`
- `debt_amount_raw`
- `health_factor_wad`
- `ltv_bps`
- `max_ltv_bps`
- `liquidation_threshold_bps`
- `synced_at`
- unique index:
  - (`user_address`, `chain_id`, `adapter_address`, `collateral_asset`, `debt_asset`)

`position_sync_jobs`
- `id` (pk)
- `user_address`
- `trigger` (`api`, `scheduled`, `manual`)
- `status` (`queued`, `running`, `success`, `failed`)
- `requested_at`
- `started_at`
- `finished_at`
- `error`

`rescue_events`
- `id` (pk)
- `chain_id` (fk)
- `block_number`
- `tx_hash`
- `log_index`
- `contract_address`
- `event_name`
- `exec_id`
- `user_address`
- `message_id` (nullable)
- `payload` (jsonb)
- `indexed_at`
- unique index:
  - (`chain_id`, `tx_hash`, `log_index`)

`rescue_executions`
- `id` (pk)
- `exec_id` (unique)
- `user_address`
- `source_chain_id`
- `mode` (`TOP_UP`, `REPAY`)
- `status` (`none`, `in_progress`, `completed`, `failed`, `partial`, `cancelled`)
- `ccip_message_id` (nullable)
- `source_tx_hash` (nullable)
- `destination_chain_id` (nullable)
- `last_event_at`
- `created_at`
- `updated_at`

`relay_jobs`
- `id` (pk)
- `message_id` (unique)
- `source_chain_id`
- `destination_chain_id`
- `exec_id` (nullable)
- `status` (`pending`, `running`, `success`, `failed`, `dead`)
- `attempt_count`
- `next_attempt_at`
- `last_error`
- `last_stdout` (text, nullable)
- `last_stderr` (text, nullable)
- `created_at`
- `updated_at`

---

## 8) Position Sync Workflow

Trigger:
- `POST /v1/positions/:address/sync`

Flow:
1. Validate address and chain/protocol registry is enabled.
2. Create `position_sync_jobs` row.
3. For each enabled chain and adapter:
   - call `discoverPositions(address)`.
   - normalize and upsert rows in `position_snapshots`.
4. Mark rows not returned in current sync as stale/zeroed (strategy configurable).
5. Mark job success/failure.

Caching:
- `GET /v1/positions/:address` returns last snapshots.
- response includes:
  - `syncedAt`
  - `isStale` (based on TTL, ex: 30-120s)
- optional `?refresh=true` forces sync before response.

---

## 9) Relay CCIP Workflow

Trigger source:
- Indexed `CrossChainInitiated` event from source chain.

Flow:
1. Parse `messageId`, `execId`, source chain.
2. Resolve destination chain from config mapping.
3. Upsert `relay_jobs` (`message_id` unique for idempotency).
4. Worker executes:
   - `./scripts/ops.sh cross-chain-rescue-relay <source-chain> <dest-chain> <message-id>`
5. Persist stdout/stderr, attempt count, status.
6. On failure:
   - retry with bounded backoff.
   - move to `dead` after max attempts.

Idempotency rules:
- same `message_id` must not produce duplicate successful relays.
- relay worker must acquire row-level lock before running a job.

---

## 10) Rescue History Indexing

Indexer behavior:
- Per chain block cursor (`fromBlock`, `toBlock`).
- Parse known events and store canonical `rescue_events`.
- Update aggregate row in `rescue_executions`:
  - latest status
  - message id linkage
  - source/destination chain correlation
  - timestamps

Derived terminal rules:
- `CrossChainCompleted` => terminal success for cross-chain leg.
- `CrossChainDestinationFailed` or escrow creation => terminal failed for destination leg.
- same-chain `RescueCompleted`/`RescueFailed` => terminal on source chain execution.

---

## 11) API Surface (v1)

Positions:
- `POST /v1/positions/:address/sync`
  - starts sync, returns job id and immediate status.
- `GET /v1/positions/:address`
  - returns latest cached snapshots with freshness fields.
- `GET /v1/positions/:address/sync-jobs`
  - returns recent sync jobs.

Rescues:
- `GET /v1/rescues`
  - filters:
    - `user`
    - `chainId`
    - `status`
    - `fromTs`
    - `toTs`
    - pagination
- `GET /v1/rescues/:execId`
  - aggregate execution detail + ordered event timeline.
- `GET /v1/rescues/:execId/events`
  - raw normalized event list.

Relay:
- `GET /v1/relay/jobs`
- `GET /v1/relay/jobs/:messageId`
- `POST /v1/relay/jobs/:messageId/retry`
  - manual retry for failed/dead jobs.

Health/ops:
- `GET /v1/health`
- `GET /v1/chains/status`

---

## 12) Operational Requirements

Config/env:
- RPC URLs per chain.
- Contract addresses per chain (from config artifact + env override).
- Relay command path (`scripts/ops.sh`) and timeout.
- Max relay retries/backoff.
- Position cache TTL.

Observability:
- structured logs with `chainId`, `execId`, `messageId`, `jobId`.
- metrics:
  - sync duration/failures
  - indexer lag (latestBlock - indexedBlock)
  - relay success rate
  - relay retry/dead counts

---

## 13) Security and Safety

- API key / auth guard for mutating endpoints:
  - `/positions/:address/sync`
  - relay retry endpoints
- Address validation and input sanitization.
- Command execution allowlist:
  - only predefined relay command template.
- Do not store private keys in DB.
- Minimize PII (only public addresses and on-chain data).

---

## 14) Acceptance Criteria

- Position sync:
  - API-triggered sync works for Ethereum Sepolia + Base Sepolia.
  - snapshots persisted and queryable.
- Relay:
  - `CrossChainInitiated` event creates relay job.
  - relay worker runs script and records outcome.
  - idempotent behavior for duplicate `messageId`.
- History:
  - rescue timeline query returns consistent event ordering.
  - `execId` view includes same-chain and cross-chain lifecycle linkage.
- Reliability:
  - retries/backoff works for relay failures.
  - indexer resumes from persisted cursor.

---

## 15) Validation Checklist

- [ ] Trigger sync API and verify `position_snapshots` rows updated.
- [ ] Verify stale cache behavior and `refresh=true` path.
- [ ] Emit a test `CrossChainInitiated` and confirm relay job creation.
- [ ] Validate relay job executes equivalent of `ops.sh cross-chain-rescue-relay`.
- [ ] Verify rescue event ingestion for:
  - `RescueInitiated`
  - `RescueCompleted` / `RescueFailed`
  - `CrossChainInitiated`
  - `CrossChainCompleted` / `CrossChainDestinationFailed`
- [ ] Confirm `GET /v1/rescues/:execId` returns complete timeline.
- [ ] Confirm duplicate indexing protection by (`chain_id`, `tx_hash`, `log_index`).
- [ ] Confirm duplicate relay protection by unique `message_id`.

