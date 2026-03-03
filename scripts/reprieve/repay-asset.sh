#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/reprieve/repay-asset.sh <chain> <symbol> <AAVE|COMPOUND|MORPHO> <amount>

Example:
  ./scripts/reprieve/repay-asset.sh ethereum-sepolia USDC MORPHO 500
EOF
}

chain="${1:-}"
symbol="${2:-}"
protocol="${3:-}"
amount="${4:-}"

if [ -z "$chain" ] || [ -z "$symbol" ] || [ -z "$protocol" ] || [ -z "$amount" ]; then
  usage
  exit 1
fi

"$ROOT_DIR/scripts/ops.sh" repay-asset "$chain" "$symbol" "$protocol" "$amount"

