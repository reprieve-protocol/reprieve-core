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
- `docker compose up -d`
- `docker compose down`

## Notes
- `ETHEREUM_SEPOLIA_RPC_URL` and `BASE_SEPOLIA_RPC_URL` are required at startup.
- `CONTRACTS_CONFIG_DIR` defaults to `../contracts/config`.
