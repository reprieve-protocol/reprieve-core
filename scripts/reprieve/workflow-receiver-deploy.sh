#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/reprieve/workflow-receiver-deploy.sh <ethereum-sepolia|base-sepolia>

Required env:
  CRE_FORWARDER=0x...

Optional env:
  AUTHORIZE_WORKFLOW_RECEIVER=true|false   (default: true)
EOF
}

chain="${1:-}"
if [ -z "$chain" ]; then
  usage
  exit 1
fi

"$ROOT_DIR/scripts/ops.sh" workflow-receiver-deploy "$chain"
