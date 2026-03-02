# Contract Ops Runbook

This runbook is the human-friendly entrypoint for deploying and operating demo lending + Reprieve contracts.

## 1) Setup

1. Copy `.env.example` to `.env`.
2. Fill RPC URLs and deployer keys.
3. Optional: set workflow/user/minter keys for demo runs.
4. For cross-chain demo, set `SOURCE_CHAIN_SELECTOR` and `DEST_CHAIN_SELECTOR`.
5. For mock programmable transfer mode, set:
   - `MOCK_CCIP_ROUTER`
   - `WIRE_MOCK_BRIDGE=true`
   - `MOCK_BRIDGE_SOURCE_TOKEN` and `MOCK_BRIDGE_DEST_TOKEN`
   - `BRIDGE_ADMIN_PRIVATE_KEY` (token admin key, defaults to `MINTER_PRIVATE_KEY`)
   - If omitted, ops defaults lane mapping to collateral-class transfer (`source collateral -> destination collateral`).
6. Select rescue action mode (optional, default `TOP_UP`):
   - `RESCUE_MODE=TOP_UP` for collateral top-up rescue.
   - `RESCUE_MODE=REPAY` for debt repay rescue.
7. Mode-specific amounts:
   - top-up: `RESCUE_TOPUP_COLLATERAL`, `CROSS_TOPUP_COLLATERAL`
   - repay: `RESCUE_REPAY_DEBT`, `CROSS_REPAY_DEBT`
   - transfer source amount: `RESCUE_WITHDRAW_COLLATERAL`, `CROSS_TRANSFER_COLLATERAL`
8. If you already have deployed collateral/debt tokens, set:
   - `COLLATERAL_ASSET`
   - `DEBT_ASSET`
   (then `DeployLendingStack` will reuse them instead of deploying mocks)

## 2) One Command Entry

Use the centralized operator script:

```bash
./scripts/ops.sh <command> <chain>
```

Supported `chain` values:
- `ethereum-sepolia`
- `base-sepolia`

## 3) Main Workflows

### A. Deploy only demo lending stack (one chain)

```bash
./scripts/ops.sh lending-deploy ethereum-sepolia
```

What it does:
- Deploys primitives (tokens + oracle)
- Deploys Aave/Compound/Morpho mocks
- Wires engine operators/oracle/risk params
- Deploys adapters
- Writes all addresses to chain config:
  - `contracts/config/ethereum-sepolia.json`
  - or `contracts/config/base-sepolia.json`

Token reuse mode:
- If `COLLATERAL_ASSET` and `DEBT_ASSET` are provided in `.env`, token deployment is skipped and these addresses are wired into all lending mocks/adapters.
- Optional: `PRICE_ORACLE` to reuse external oracle.

### B. Deploy only Reprieve stack (one chain)

```bash
./scripts/ops.sh reprieve-deploy ethereum-sepolia
```

What it does:
- Deploys registry/log/escrow/executor/receiver/health monitor
- Wires writers/depositors/workflow/reporter
- Auto-reads adapter addresses from chain config if not set in env
- Writes artifact:
  - `contracts/config/reprieve-stack-<chainId>.json`

### C. Deploy mock CCIP router (one chain)

```bash
./scripts/ops.sh mock-router-deploy ethereum-sepolia
```

What it does:
- Deploys `MockCCIPRouter`
- Sets source chain selector and default mock fees
- Writes artifact:
  - `contracts/config/mock-ccip-router-<chainId>.json`

### D. Relay mock CCIP message across two real testnets

```bash
./scripts/ops.sh mock-relay ethereum-sepolia base-sepolia <message-id>
```

What it does:
- Reads the stored message from source-chain `MockCCIPRouter`.
- Exports message data/token fields to `contracts/config/mock-relay-<sourceChainId>.env`.
- Broadcasts destination-chain relay tx via `RelayExternalMockMessage`.
- Calls destination router `deliverExternalMessage(...)`, which mints destination token to receiver and calls `ccipReceive`.

### E. Full deploy on one chain (lending + reprieve)

```bash
./scripts/ops.sh full-deploy ethereum-sepolia
```

### F. Verify deployed Reprieve wiring

```bash
./scripts/ops.sh reprieve-verify ethereum-sepolia
```

### G. Run demo rescue scenarios

Same-chain:
```bash
./scripts/ops.sh same-chain-demo ethereum-sepolia
```
Notes:
- Same-chain rescue now uses collateral top-up on target positions (debt is unchanged).
- Set `RESCUE_MODE=REPAY` to run debt repay flow.
- In same-chain `REPAY` mode, source withdraw asset and repay asset must match (no swap inside executor).
- In same-chain `REPAY` mode, the script deploys a temporary reversed source Aave-like pool/adapter (`debt` as source collateral) so withdrawn source asset can repay target debt directly.
- Optional repay setup knobs: `REPAY_SOURCE_DEBT_MINT`, `REPAY_SOURCE_SUPPLY_DEBT`, `REPAY_SOURCE_ENGINE_LIQ_COLLATERAL`.

Cross-chain leg (CCIP flow):
```bash
./scripts/ops.sh cross-chain-demo ethereum-sepolia
```
Notes:
- `DEST_RECEIVER` auto-resolves from opposite-chain `reprieve-stack-<chainId>.json` artifact when available.
- `SOURCE_SENDER` auto-resolves to source chain `RescueExecutor`.
- `TARGET_ADAPTER` defaults to opposite-chain `CompoundLikeAdapter` from config.
- `MOCK_BRIDGE_SOURCE_TOKEN` defaults to source `COLLATERAL_ASSET`.
- `MOCK_BRIDGE_DEST_TOKEN` defaults by mode:
  - `TOP_UP`: opposite-chain collateral token
  - `REPAY`: opposite-chain debt token

Hedging-oriented repay example:
- Configure `RESCUE_MODE=REPAY`.
- Example branch A (WETH dump): withdraw USDC source leg and repay USDC target debt.
- Example branch B (WETH pump): withdraw WETH source leg and repay WETH target debt.

### H. Wire CCIP lane permissions/config

Source-side lane wiring (executor + optional mock router lane/token mapping):
```bash
./scripts/ops.sh ccip-wire-source ethereum-sepolia
```
Note: `DEST_RECEIVER` auto-resolves from opposite-chain Reprieve artifact when available.

Destination-side lane wiring (receiver source allowlist + sender allowlist):
```bash
./scripts/ops.sh ccip-wire-dest base-sepolia
```
Note: `SOURCE_SENDER` auto-resolves from opposite-chain `RescueExecutor` when available.

## 4) Utility Commands

Print loaded addresses:
```bash
./scripts/ops.sh addresses ethereum-sepolia
```

Run build/tests/check scripts:
```bash
./scripts/ops.sh checks
```

## 5) Direct Script Mapping (if needed)

- Lending one-shot deploy:
  - `contracts/script/demo/DeployLendingStack.s.sol`
- Reprieve one-shot deploy:
  - `contracts/script/reprieve/DeployReprieveStack.s.sol`
- Mock router one-shot deploy:
  - `contracts/script/reprieve/DeployMockCCIPRouter.s.sol`
- Reprieve verify:
  - `contracts/script/reprieve/VerifyReprieveStack.s.sol`
- Same-chain scenario:
  - `contracts/script/reprieve/RunSameChainRescue.s.sol`
- Cross-chain scenario:
  - `contracts/script/reprieve/RunCrossChainRescue.s.sol`
- Lane wiring:
  - `contracts/script/reprieve/WireCcipLane.s.sol`
- Failure + escrow recovery:
  - `contracts/script/reprieve/RunFailureScenarios.s.sol`
  - `contracts/script/reprieve/RunEscrowRecovery.s.sol`

## 6) Suggested Process (Lowest Friction)

1. `./scripts/ops.sh full-deploy ethereum-sepolia`
2. `./scripts/ops.sh full-deploy base-sepolia`
3. `./scripts/ops.sh mock-router-deploy ethereum-sepolia` (and/or base)
4. `./scripts/ops.sh reprieve-verify ethereum-sepolia`
5. `./scripts/ops.sh ccip-wire-source ethereum-sepolia`
6. `./scripts/ops.sh ccip-wire-dest base-sepolia`
7. `./scripts/ops.sh same-chain-demo ethereum-sepolia`
8. `./scripts/ops.sh cross-chain-demo ethereum-sepolia`
9. `./scripts/ops.sh mock-relay ethereum-sepolia base-sepolia <message-id>`
