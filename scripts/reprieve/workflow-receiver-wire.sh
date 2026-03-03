#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/reprieve/workflow-receiver-wire.sh <ethereum-sepolia|base-sepolia>

Optional env:
  WORKFLOW_RECEIVER=0x...
  CRE_FORWARDER=0x...
  AUTHORIZE_WORKFLOW_RECEIVER=true|false
  WF_EXPECTED_AUTHOR=0x...
EOF
}

chain="${1:-}"
if [ -z "$chain" ]; then
  usage
  exit 1
fi

"$ROOT_DIR/scripts/ops.sh" workflow-receiver-wire "$chain"
