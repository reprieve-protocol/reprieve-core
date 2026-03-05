# Reprieve Backend (Slide 0 Foundation)

## Prerequisites
- Node.js 20+
- npm 10+
- Docker

## Quick Start
1. `cd backend`
2. `cp .env.example .env`
3. `docker compose up -d`
4. `npm install`
5. `npm run migration:run`
6. `npm run dev`

## Scripts
- `npm run dev`
- `npm run test`
- `npm run migration:run`
- `npm run lint`
- `npm run indexer:reset` (clears rescue events/executions and resets chain cursors)
- `npm run indexer:once`
- `npm run indexer:start`
- `npm run relay:once`
- `npm run relay:start`
- `docker compose up -d`
- `docker compose down`

## Docker Deployment (API + Indexer + Relay)
- The compose stack includes:
  - `postgres`
  - `api` (Nest HTTP API)
  - `indexer` (event indexer worker)
  - `relay` (cross-chain relay worker)
- Start all services:
  - `docker compose up -d --build`
- Follow logs:
  - `docker compose logs -f api`
  - `docker compose logs -f indexer`
  - `docker compose logs -f relay`
- Stop stack:
  - `docker compose down`
- Important:
  - Contract config is bundled in this folder at `backend/contracts-config`.
  - `CONTRACTS_CONFIG_DIR` is set automatically in compose to `/app/contracts-config`.

## Notes
- `ETHEREUM_SEPOLIA_RPC_URL` and `BASE_SEPOLIA_RPC_URL` are required at startup.
- `CONTRACTS_CONFIG_DIR` defaults to `./contracts-config`.
- `INDEXER_RUN_IN_API` defaults to `true` (API process also runs the indexer loop).
  - Set `INDEXER_RUN_IN_API=false` when running a dedicated `indexer:start` process to avoid duplicate indexers.
- Relay worker submits EVM tx directly (no shell-out). Set one of:
  - `RELAY_SIGNER_PRIVATE_KEY`
  - chain-specific `ETHEREUM_SEPOLIA_PRIVATE_KEY` / `BASE_SEPOLIA_PRIVATE_KEY`
