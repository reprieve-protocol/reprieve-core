#!/bin/bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib/load-env.sh"

echo "=== Reprieve Address Snapshot ==="
echo ""

print_var() {
  local name="$1"
  local val="${!name:-}"
  if [ -z "$val" ]; then
    echo "  $name: MISSING"
  else
    echo "  $name: $val"
  fi
}

echo "Core contracts:"
print_var "ADAPTER_REGISTRY"
print_var "RESCUE_LOG"
print_var "RESCUE_ESCROW"
print_var "RESCUE_EXECUTOR"
print_var "CCIP_RECEIVER"
print_var "HEALTH_MONITOR"
echo ""

echo "Demo lending + adapters:"
print_var "COLLATERAL_ASSET"
print_var "DEBT_ASSET"
print_var "AAVE_POOL"
print_var "COMPOUND_MARKET"
print_var "MORPHO_MARKET"
print_var "AAVE_ADAPTER"
print_var "COMPOUND_ADAPTER"
print_var "MORPHO_ADAPTER"
echo ""

echo "CCIP lane:"
print_var "CCIP_ROUTER"
print_var "SOURCE_EXECUTOR"
print_var "SOURCE_AAVE_POOL"
print_var "SOURCE_AAVE_ADAPTER"
print_var "TARGET_ADAPTER"
print_var "DEST_RECEIVER"
print_var "DEST_CHAIN_SELECTOR"
print_var "SOURCE_CHAIN_SELECTOR"
print_var "SOURCE_SENDER"
echo ""

echo "Keys:"
print_var "PRIVATE_KEY"
print_var "WORKFLOW_PRIVATE_KEY"
print_var "USER_PRIVATE_KEY"
print_var "MINTER_PRIVATE_KEY"
