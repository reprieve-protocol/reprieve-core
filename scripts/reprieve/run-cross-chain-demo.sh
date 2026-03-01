#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONTRACTS_DIR="$ROOT_DIR/contracts"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/load-env.sh"

RPC_URL="${RPC_URL:-${ETHEREUM_SEPOLIA_RPC:-}}"
if [ -z "$RPC_URL" ]; then
  echo "Missing RPC URL. Set RPC_URL or ETHEREUM_SEPOLIA_RPC."
  exit 1
fi

echo "=== Run Cross-Chain Rescue Demo ==="
echo "RPC: $RPC_URL"
echo ""

cd "$CONTRACTS_DIR"

forge script script/reprieve/RunCrossChainRescue.s.sol:RunCrossChainRescue \
  --rpc-url "$RPC_URL" \
  --broadcast \
  -vvvv

if [ "${RUN_FAILURE_SCENARIOS:-0}" = "1" ]; then
  echo ""
  echo "=== Run Failure Scenarios ==="
  forge script script/reprieve/RunFailureScenarios.s.sol:RunFailureScenarios \
    --rpc-url "$RPC_URL" \
    --broadcast \
    -vvvv
fi

if [ "${RUN_ESCROW_RECOVERY:-0}" = "1" ]; then
  echo ""
  echo "=== Run Escrow Recovery ==="
  forge script script/reprieve/RunEscrowRecovery.s.sol:RunEscrowRecovery \
    --rpc-url "$RPC_URL" \
    --broadcast \
    -vvvv
fi

echo ""
echo "Cross-chain demo run complete."
