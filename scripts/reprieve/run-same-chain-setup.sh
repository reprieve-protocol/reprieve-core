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

echo "=== Setup Same-Chain Rescue Positions ==="
echo "RPC: $RPC_URL"
echo "Mode: ${RESCUE_MODE:-TOP_UP}"
echo ""

cd "$CONTRACTS_DIR"
forge script script/reprieve/SameChainRescueSetup.s.sol:SameChainRescueSetup \
  --rpc-url "$RPC_URL" \
  --broadcast \
  -vvvv

echo ""
echo "Same-chain setup complete."
