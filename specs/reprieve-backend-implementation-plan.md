# Reprieve Backend Implementation Plan (Vertical Slides)

This plan implements [reprieve-backend-nest-design.md](/Users/sniperman/code/reprieve/specs/reprieve-backend-nest-design.md) with:
- NestJS
- PostgreSQL
- supported chains: Ethereum Sepolia + Base Sepolia

---

## Slide 0 - Backend Foundation and Project Setup

### Status
- Completed (user-validated).

### Development Scope
- Bootstrap backend service and define module boundaries.
- Establish runtime config, chain registry, and environment loading.

### Build Tasks
- Scaffold Nest project in `backend/` (fixed location).
- Create modules:
  - `chains`
  - `positions`
  - `relay`
  - `rescue-history`
  - `persistence`
  - `api`
- Add configuration package:
  - chain metadata (`ethereum-sepolia`, `base-sepolia`)
  - artifact-based address loader with env override.
- Add global DTO validation and error response format.
- Add local Postgres Docker setup:
  - `backend/docker-compose.yml` (postgres service)
  - `.env.example` entries for DB connection
  - persistent volume + healthcheck

### Testing Scope
- Boot test for Nest app.
- Config parsing tests for valid/invalid chain/env values.
- DB connectivity test against dockerized Postgres.

### Script Scope
- Add:
  - `cd backend && npm run dev`
  - `cd backend && npm run test`
  - `cd backend && npm run migration:run`
  - `cd backend && npm run lint`
  - `cd backend && docker compose up -d`
  - `cd backend && docker compose down`

### Acceptance Criteria
- Service boots with chain-aware config.
- Invalid config fails at startup with actionable errors.
- Local Postgres runs via Docker and backend connects successfully.

### Validation Checklist
- [x] App starts locally with `.env`.
- [x] Startup fails when required RPC/config values are missing.
- [x] Module wiring smoke tests pass.
- [x] `backend/docker-compose.yml` starts healthy postgres.
- [x] Backend can run migrations against dockerized postgres.

---

## Slide 1 - Persistence Layer and Schema Migrations

### Status
- In progress: schema/migrations/entities/tests/scripts implemented; live Postgres validation commands pending in your local environment.

### Development Scope
- Implement Postgres schema for positions, events, rescue executions, and relay jobs.

### Build Tasks
- Add ORM setup (TypeORM or Prisma; choose one and keep consistent).
- Implement migrations/tables:
  - `chains`
  - `protocol_adapters`
  - `position_snapshots`
  - `position_sync_jobs`
  - `rescue_events`
  - `rescue_executions`
  - `relay_jobs`
- Add unique indexes:
  - `rescue_events(chain_id, tx_hash, log_index)`
  - `relay_jobs(message_id)`
  - `rescue_executions(exec_id)`

### Testing Scope
- Migration up/down tests.
- Repository CRUD + uniqueness tests.

### Script Scope
- Add local DB bootstrap script:
  - `scripts/backend/db-up.sh` (docker compose or local postgres).

### Acceptance Criteria
- Migrations create all required tables/indexes.
- Upserts are idempotent for events and relay jobs.

### Validation Checklist
- [ ] `migration:run` succeeds on clean DB.
- [ ] Duplicate event insert is rejected/ignored by unique key.
- [ ] Relay job dedup by `message_id` works.

---

## Slide 2 - Position Sync Service and APIs

### Status
- In progress: endpoints/services/adapter-read path implemented with unit tests; live RPC+DB endpoint smoke validation pending in your environment.

### Development Scope
- API-triggered position sync across supported chains/protocol adapters.
- Cached query endpoint with freshness metadata.

### Build Tasks
- Implement `POST /v1/positions/:address/sync`.
- Implement `GET /v1/positions/:address` with optional `?refresh=true`.
- Implement `GET /v1/positions/:address/sync-jobs`.
- Adapter read path:
  - call `discoverPositions(user)` on each configured adapter.
  - normalize raw values to persisted snapshot rows.
- Job status lifecycle:
  - `queued -> running -> success/failed`.

### Testing Scope
- Sync happy path (both chains, all enabled adapters).
- Partial failure handling (one chain RPC error).
- Refresh and stale cache behavior.

### Script Scope
- Add seed/dev command:
  - `npm run backend:sync -- <userAddress>`.

### Acceptance Criteria
- Sync API updates position snapshots for user across chains.
- Read API returns latest snapshots with `syncedAt`/freshness.

### Validation Checklist
- [x] Sync endpoint creates and completes a sync job.
- [x] Position rows are upserted correctly.
- [x] `refresh=true` forces new sync.

---

## Slide 3 - Event Indexer Core

### Status
- In progress: indexer worker, cursor tracking, event decoding, CLI commands, and idempotency tests implemented; live chain scan validation pending in your environment.

### Development Scope
- Index rescue-related events from both chains with persisted block cursors.

### Build Tasks
- Implement indexer worker:
  - reads chain cursor
  - scans block windows
  - decodes targeted events
  - persists normalized `rescue_events`
- Events to ingest:
  - `RescueInitiated`
  - `RescueStepCompleted`
  - `RescueCompleted`
  - `RescueFailed`
  - `CrossChainInitiated`
  - `CrossChainCompleted`
  - `CrossChainDestinationFailed`
  - `EscrowCreated` (if emitted)
- Add cursor table or cursor columns in `chains`.

### Testing Scope
- Decoder tests with fixture logs.
- Reorg-safe/idempotent re-scan behavior for same block range.

### Script Scope
- Add:
  - `npm run indexer:start`
  - `npm run indexer:once`.

### Acceptance Criteria
- Indexer can catch up from genesis/start block and resume from cursor.
- Duplicate ingest attempts do not create duplicate rows.

### Validation Checklist
- [x] Cursor advances after successful batch.
- [x] Re-running same batch keeps event count stable.
- [ ] Events from both chains are ingested.

---

## Slide 4 - Rescue Execution Projection and Query APIs

### Status
- Completed in code/tests: projection service, rebuild command, and rescue query APIs implemented with status-transition and timeline tests; live API validation pending in your environment.

### Development Scope
- Build `rescue_executions` aggregate projection from raw events.
- Expose rescue history APIs.

### Build Tasks
- Projection logic:
  - upsert `rescue_executions` by `exec_id`
  - derive mode/status/message linkage
  - correlate source and destination chain events.
- Implement APIs:
  - `GET /v1/rescues`
  - `GET /v1/rescues/:execId`
  - `GET /v1/rescues/:execId/events`

### Testing Scope
- Timeline ordering tests.
- Status transition correctness for:
  - same-chain success/fail
  - cross-chain dispatched/success/fail.

### Script Scope
- Add internal projection rebuild command:
  - `npm run projection:rebuild`.

### Acceptance Criteria
- `execId` detail endpoint returns consistent lifecycle timeline.
- Filtering/pagination works on rescue list endpoint.

### Validation Checklist
- [x] Same-chain rescue displays source lifecycle correctly.
- [x] Cross-chain rescue displays source+destination lifecycle correctly.
- [x] Event timeline is deterministic and ordered.

---

## Slide 5 - Relay Worker (Mock CCIP Relay Automation)

### Development Scope
- Drive relay jobs from indexed `CrossChainInitiated` events.
- Execute existing script pipeline with retry/backoff.

### Build Tasks
- On event ingest, upsert `relay_jobs` by `message_id`.
- Relay worker:
  - lock pending job
  - execute `./scripts/ops.sh cross-chain-rescue-relay <source> <dest> <message-id>`
  - persist stdout/stderr + status
  - retry on failure with bounded backoff
  - dead-letter after max attempts.
- API surface:
  - `GET /v1/relay/jobs`
  - `GET /v1/relay/jobs/:messageId`
  - `POST /v1/relay/jobs/:messageId/retry`

### Testing Scope
- Success path end-to-end from event -> relay success.
- Retry path and dead-letter transition.
- Idempotency on duplicate `message_id`.

### Script Scope
- Add runbook script:
  - `scripts/backend/relay-replay.sh <message-id>`.

### Acceptance Criteria
- Relay jobs are created automatically from source-chain cross-chain events.
- Relay execution is idempotent and observable.

### Validation Checklist
- [ ] `CrossChainInitiated` creates one relay job.
- [ ] Success updates status to `success`.
- [ ] Repeated trigger for same message keeps one terminal job.
- [ ] Manual retry endpoint works for failed/dead jobs.

---

## Slide 6 - Security, Observability, and Operations

### Development Scope
- Add operational safety and telemetry.

### Build Tasks
- API auth guard for mutating endpoints:
  - sync trigger
  - relay retry.
- Structured logs:
  - include `chainId`, `execId`, `messageId`, `jobId`.
- Health endpoints:
  - `GET /v1/health`
  - `GET /v1/chains/status`
- Metrics:
  - index lag
  - sync latency
  - relay success/failure/retry counts.

### Testing Scope
- Unauthorized request rejection tests.
- Health/metrics endpoint tests.

### Script Scope
- Add:
  - `npm run smoke:backend`.

### Acceptance Criteria
- Mutating APIs require auth.
- Operators can observe lag/errors and replay failures.

### Validation Checklist
- [ ] Unauthorized sync/relay requests are denied.
- [ ] Health endpoint reflects DB/RPC/indexer status.
- [ ] Metrics expose relay and indexing KPIs.

---

## Slide 7 - End-to-End Demo Readiness

### Development Scope
- Validate the complete backend loop with deployed contracts and CRE flow.

### Build Tasks
- Run integrated scenario:
  1. call position sync API
  2. execute rescue (same-chain + cross-chain via CRE/scripts)
  3. index events
  4. auto-relay cross-chain message
  5. query rescue history APIs
- Produce backend runbook for demo operator.

### Testing Scope
- E2E test scripts against Sepolia/Base deployments.
- Failure scenario validation (relay failure and retry).

### Script Scope
- Add:
  - `scripts/backend/e2e-demo.sh`
  - `scripts/backend/check-indexer-lag.sh`.

### Acceptance Criteria
- Demo operator can run one documented flow and see:
  - synced positions
  - relay execution
  - indexed rescue timeline.

### Validation Checklist
- [ ] Same-chain rescue appears in `/v1/rescues`.
- [ ] Cross-chain rescue creates and completes relay job.
- [ ] Destination terminal event is reflected in execution detail.
- [ ] Demo runbook is reproducible on a clean environment.

---

## Final Deliverables

- Backend service (NestJS) with Postgres schema + migrations.
- Position sync APIs.
- Event indexer + rescue history projection.
- Relay worker and relay APIs.
- Demo runbook and E2E validation scripts.
