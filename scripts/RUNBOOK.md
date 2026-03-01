# Contract Ops Runbook

This runbook is the human-friendly entrypoint for deploying and operating demo lending + Reprieve contracts.

## 1) Setup

1. Copy `.env.example` to `.env`.
2. Fill RPC URLs and deployer keys.
3. Optional: set workflow/user/minter keys for demo runs.
4. For cross-chain demo, set `SOURCE_CHAIN_SELECTOR` and `DEST_CHAIN_SELECTOR`.

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

### C. Full deploy on one chain (lending + reprieve)

```bash
./scripts/ops.sh full-deploy ethereum-sepolia
```

### D. Verify deployed Reprieve wiring

```bash
./scripts/ops.sh reprieve-verify ethereum-sepolia
```

### E. Run demo rescue scenarios

Same-chain:
```bash
./scripts/ops.sh same-chain-demo ethereum-sepolia
```

Cross-chain leg (CCIP flow):
```bash
./scripts/ops.sh cross-chain-demo ethereum-sepolia
```

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
- Reprieve verify:
  - `contracts/script/reprieve/VerifyReprieveStack.s.sol`
- Same-chain scenario:
  - `contracts/script/reprieve/RunSameChainRescue.s.sol`
- Cross-chain scenario:
  - `contracts/script/reprieve/RunCrossChainRescue.s.sol`
- Failure + escrow recovery:
  - `contracts/script/reprieve/RunFailureScenarios.s.sol`
  - `contracts/script/reprieve/RunEscrowRecovery.s.sol`

## 6) Suggested Process (Lowest Friction)

1. `./scripts/ops.sh full-deploy ethereum-sepolia`
2. `./scripts/ops.sh reprieve-verify ethereum-sepolia`
3. `./scripts/ops.sh same-chain-demo ethereum-sepolia`
4. `./scripts/ops.sh cross-chain-demo ethereum-sepolia`
5. Repeat on `base-sepolia` when needed.
