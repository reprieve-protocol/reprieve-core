#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/reprieve/set-oracle-price.sh <ethereum-sepolia|base-sepolia> <symbol> <price-usd>

Examples:
  ./scripts/reprieve/set-oracle-price.sh ethereum-sepolia WETH 1850.25
  ./scripts/reprieve/set-oracle-price.sh base-sepolia USDC 1
EOF
}

chain="${1:-}"
symbol="${2:-}"
price="${3:-}"

if [ -z "$chain" ] || [ -z "$symbol" ] || [ -z "$price" ]; then
  usage
  exit 1
fi

"$ROOT_DIR/scripts/ops.sh" set-oracle-price "$chain" "$symbol" "$price"

