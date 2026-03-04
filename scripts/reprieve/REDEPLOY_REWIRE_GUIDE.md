# Reprieve Redeploy + Rewire Guide (Sepolia + Base Sepolia)

This runbook is for redeploying Reprieve contracts after `RescueExecutor` logic updates, then rewiring workflow + CCIP lanes.

## Scope

- Chains:
  - `ethereum-sepolia`
  - `base-sepolia`
- Keep existing lending stack, tokens, and mock router.
- Redeploy:
  - Reprieve stack (`RescueExecutor`, `CCIPReceiver`, `RescueLog`, `RescueEscrow`, etc.)
  - Workflow receiver (`ReprieveWorkflowReceiver`) because it has immutable `rescueExecutor`.

## Prerequisites

- `.env` loaded with deploy keys and RPCs.
- CRE forwarders set:
  - `ETHEREUM_SEPOLIA_CRE_FORWARDER`
  - `BASE_SEPOLIA_CRE_FORWARDER`
- Workflow identity vars set (author required; ID/name optional):
  - `WF_EXPECTED_AUTHOR`
  - `WF_EXPECTED_WORKFLOW_ID` (optional; zero to disable)
  - `WF_EXPECTED_WORKFLOW_NAME` (optional; zero to disable)
- Mock CCIP routers already deployed on both chains and present in config/env.

## 1) Redeploy Reprieve Stack

```bash
./scripts/ops.sh reprieve-deploy ethereum-sepolia
./scripts/ops.sh reprieve-deploy base-sepolia
```

## 2) Redeploy + Wire Workflow Receiver

```bash
# Ethereum Sepolia
CRE_FORWARDER=$ETHEREUM_SEPOLIA_CRE_FORWARDER \
./scripts/ops.sh workflow-receiver-deploy ethereum-sepolia

WF_EXPECTED_AUTHOR=$WF_EXPECTED_AUTHOR \
WF_EXPECTED_WORKFLOW_ID=${WF_EXPECTED_WORKFLOW_ID:-0x0000000000000000000000000000000000000000000000000000000000000000} \
WF_EXPECTED_WORKFLOW_NAME=${WF_EXPECTED_WORKFLOW_NAME:-0x00000000000000000000} \
./scripts/ops.sh workflow-receiver-wire ethereum-sepolia

# Base Sepolia
CRE_FORWARDER=$BASE_SEPOLIA_CRE_FORWARDER \
./scripts/ops.sh workflow-receiver-deploy base-sepolia

WF_EXPECTED_AUTHOR=$WF_EXPECTED_AUTHOR \
WF_EXPECTED_WORKFLOW_ID=${WF_EXPECTED_WORKFLOW_ID:-0x0000000000000000000000000000000000000000000000000000000000000000} \
WF_EXPECTED_WORKFLOW_NAME=${WF_EXPECTED_WORKFLOW_NAME:-0x00000000000000000000} \
./scripts/ops.sh workflow-receiver-wire base-sepolia
```

## 3) Rewire Destination Allowlists (Sender/Source Chain)

Run once per destination chain:

```bash
./scripts/ops.sh ccip-wire-dest ethereum-sepolia
./scripts/ops.sh ccip-wire-dest base-sepolia
```

## 4) Rewire Source Lanes + Token Mappings (Mock Router)

Run per direction + per asset mapping.

### ETH -> BASE (TOP_UP collateral mapping, usually WETH->WETH)

```bash
CONFIGURE_MOCK_ROUTER=true RESCUE_MODE=TOP_UP \
MOCK_BRIDGE_SOURCE_TOKEN=$ETH_WETH \
MOCK_BRIDGE_DEST_TOKEN=$BASE_WETH \
./scripts/ops.sh ccip-wire-source ethereum-sepolia
```

### ETH -> BASE (REPAY mapping, usually USDC->USDC)

```bash
CONFIGURE_MOCK_ROUTER=true RESCUE_MODE=REPAY \
MOCK_BRIDGE_SOURCE_TOKEN=$ETH_USDC \
MOCK_BRIDGE_DEST_TOKEN=$BASE_USDC \
./scripts/ops.sh ccip-wire-source ethereum-sepolia
```

### BASE -> ETH (TOP_UP collateral mapping)

```bash
CONFIGURE_MOCK_ROUTER=true RESCUE_MODE=TOP_UP \
MOCK_BRIDGE_SOURCE_TOKEN=$BASE_WETH \
MOCK_BRIDGE_DEST_TOKEN=$ETH_WETH \
./scripts/ops.sh ccip-wire-source base-sepolia
```

### BASE -> ETH (REPAY mapping)

```bash
CONFIGURE_MOCK_ROUTER=true RESCUE_MODE=REPAY \
MOCK_BRIDGE_SOURCE_TOKEN=$BASE_USDC \
MOCK_BRIDGE_DEST_TOKEN=$ETH_USDC \
./scripts/ops.sh ccip-wire-source base-sepolia
```

## 5) Required User Approval for Aave Source Withdraw

Rescue withdraw from Aave source needs user approval of aToken to adapter.

```bash
./scripts/ops.sh approve-aave-receipt ethereum-sepolia
./scripts/ops.sh approve-aave-receipt base-sepolia
```

## 6) Verify Addresses and Wiring

```bash
./scripts/ops.sh addresses ethereum-sepolia
./scripts/ops.sh addresses base-sepolia
```

Also verify logs include successful:
- `workflow-receiver-wire` checks
- `ccip-wire-source` lane/token mapping events
- `ccip-wire-dest` source sender allowlist events

## 7) Smoke Tests

### Same-chain

```bash
RESCUE_MODE=TOP_UP ./scripts/ops.sh same-chain-demo ethereum-sepolia
RESCUE_MODE=REPAY  ./scripts/ops.sh same-chain-demo ethereum-sepolia
```

### Cross-chain (4-phase flow)

```bash
# 1) setup source
RESCUE_MODE=TOP_UP ./scripts/ops.sh cross-chain-rescue-setup-source ethereum-sepolia

# 2) setup destination
RESCUE_MODE=TOP_UP ./scripts/ops.sh cross-chain-rescue-setup-destination base-sepolia

# 3) execute source leg (creates CCIP message id)
RESCUE_MODE=TOP_UP ./scripts/ops.sh cross-chain-rescue-execute ethereum-sepolia

# 4) relay to destination (use emitted message id or 'latest')
./scripts/ops.sh cross-chain-rescue-relay ethereum-sepolia base-sepolia latest
```

Repeat with `RESCUE_MODE=REPAY` for hedge repay path.

## Notes

- After this redeploy, cross-chain source leg now withdraws from source position first (no executor-float rescue).
- If CRE uses `workflowReceiverAddress`/`rescueExecutor` directly, update CRE configs from latest artifacts after redeploy.
