#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ $# -ne 3 ]]; then
  cat <<'EOF'
Usage:
  ./scripts/reprieve/check-ccip-mapping.sh <source-chain> <dest-chain|dest-selector> <source-symbol|source-token-address>

Examples:
  ./scripts/reprieve/check-ccip-mapping.sh ethereum-sepolia base-sepolia WETH
  ./scripts/reprieve/check-ccip-mapping.sh ethereum-sepolia 10344971235874465080 0x4c87EA388AdE37f6A556146B4fF6ff2A12192968
EOF
  exit 1
fi

source_chain="$1"
dest_chain_or_selector="$2"
source_token="$3"

"$ROOT_DIR/scripts/ops.sh" ccip-mapping-check "$source_chain" "$dest_chain_or_selector" "$source_token"

