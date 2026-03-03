#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/reprieve/decode-onreport.sh <calldata-hex>

Example:
  ./scripts/reprieve/decode-onreport.sh 0x805f2132...
EOF
}

calldata_hex="${1:-}"
if [ -z "$calldata_hex" ]; then
  usage
  exit 1
fi

"$ROOT_DIR/scripts/ops.sh" decode-onreport "$calldata_hex"

