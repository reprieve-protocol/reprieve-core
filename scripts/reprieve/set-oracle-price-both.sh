#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/reprieve/set-oracle-price-both.sh <chain-a> <chain-b> <symbol> <price-usd>

Supported chains:
  - ethereum-sepolia
  - base-sepolia

Examples:
  ./scripts/reprieve/set-oracle-price-both.sh ethereum-sepolia base-sepolia WETH 1850.25
  ./scripts/reprieve/set-oracle-price-both.sh ethereum-sepolia base-sepolia USDC 1
EOF
}

chain_a="${1:-}"
chain_b="${2:-}"
symbol="${3:-}"
price="${4:-}"

if [ -z "$chain_a" ] || [ -z "$chain_b" ] || [ -z "$symbol" ] || [ -z "$price" ]; then
  usage
  exit 1
fi

echo "Setting ${symbol}=${price} on ${chain_a}..."
"$ROOT_DIR/scripts/ops.sh" set-oracle-price "$chain_a" "$symbol" "$price"

echo "Setting ${symbol}=${price} on ${chain_b}..."
"$ROOT_DIR/scripts/ops.sh" set-oracle-price "$chain_b" "$symbol" "$price"

echo "Done: ${symbol}=${price} updated on ${chain_a} and ${chain_b}."

