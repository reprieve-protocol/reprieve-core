1. Quick verify wiring (optional but recommended)
```bash
./scripts/ops.sh reprieve-verify ethereum-sepolia
./scripts/ops.sh reprieve-verify base-sepolia
```

2. Same-chain demos
Top-up mode:

```bash
RESCUE_MODE=TOP_UP ./scripts/ops.sh same-chain-demo ethereum-sepolia
RESCUE_MODE=TOP_UP ./scripts/ops.sh same-chain-demo base-sepolia
```

Repay mode:

```bash
RESCUE_MODE=REPAY ./scripts/ops.sh same-chain-demo ethereum-sepolia
RESCUE_MODE=REPAY ./scripts/ops.sh same-chain-demo base-sepolia
```

3. Cross-chain demo + manual relay (new flow)

Eth -> Base:

```bash
RESCUE_MODE=TOP_UP ./scripts/ops.sh cross-chain-demo ethereum-sepolia
./scripts/ops.sh cross-chain-rescue-relay ethereum-sepolia base-sepolia <message-id>
```

Base -> Eth:

```bash
RESCUE_MODE=TOP_UP ./scripts/ops.sh cross-chain-demo base-sepolia
./scripts/ops.sh cross-chain-rescue-relay base-sepolia ethereum-sepolia <message-id>
```

4. Repeat cross-chain for repay mode

```bash
RESCUE_MODE=REPAY ./scripts/ops.sh cross-chain-demo ethereum-sepolia
./scripts/ops.sh cross-chain-rescue-relay ethereum-sepolia base-sepolia <message-id>
```

```bash
RESCUE_MODE=REPAY ./scripts/ops.sh cross-chain-demo base-sepolia
./scripts/ops.sh cross-chain-rescue-relay base-sepolia ethereum-sepolia <message-id>
```