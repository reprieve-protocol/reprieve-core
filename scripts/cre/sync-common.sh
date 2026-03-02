#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMMON_DIR="$ROOT/cre/reprieve-common"
WORKFLOWS=(
  "reprieve-chainlink-api-guard-v1"
  "reprieve-quant-funding-oi-v1"
  "reprieve-quant-basis-liquidity-v1"
)

if [[ ! -f "$COMMON_DIR/types.ts" || ! -f "$COMMON_DIR/runtime.ts" ]]; then
  echo "Common files missing in $COMMON_DIR"
  exit 1
fi

if [[ ! -f "$COMMON_DIR/lib/contracts.ts" ]]; then
  echo "Common contract IO missing in $COMMON_DIR/lib/contracts.ts"
  exit 1
fi

for workflow in "${WORKFLOWS[@]}"; do
  target_dir="$ROOT/cre/$workflow"
  if [[ ! -d "$target_dir" ]]; then
    echo "Skipping missing workflow dir: $target_dir"
    continue
  fi

  cp "$COMMON_DIR/types.ts" "$target_dir/types.ts"
  cp "$COMMON_DIR/runtime.ts" "$target_dir/runtime.ts"
  mkdir -p "$target_dir/lib"
  cp "$COMMON_DIR/lib/contracts.ts" "$target_dir/lib/contracts.ts"
  echo "Synced common files -> $workflow"
done
