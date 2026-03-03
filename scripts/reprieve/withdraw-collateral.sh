#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/reprieve/withdraw-collateral.sh <chain> <symbol> <AAVE|COMPOUND|MORPHO> <amount>

Example:
  ./scripts/reprieve/withdraw-collateral.sh ethereum-sepolia WETH COMPOUND 0.5
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

"$ROOT_DIR/scripts/ops.sh" withdraw-collateral "$chain" "$symbol" "$protocol" "$amount"

