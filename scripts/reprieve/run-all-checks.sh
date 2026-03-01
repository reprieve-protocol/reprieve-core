#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONTRACTS_DIR="$ROOT_DIR/contracts"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/load-env.sh"

echo "=== Reprieve All Checks ==="
echo "Root: $ROOT_DIR"
echo ""

cd "$CONTRACTS_DIR"

if [ "${SKIP_ENV_CHECKS:-0}" != "1" ]; then
  echo "1) Environment checks"
  ./script/demo/check-env.sh
  ./script/reprieve/check-env.sh
  echo ""
else
  echo "1) Environment checks skipped (SKIP_ENV_CHECKS=1)"
  echo ""
fi

echo "2) Build"
forge build
echo ""

echo "3) Full test suite"
forge test --summary
echo ""

echo "4) ABI/code drift hashes"
forge script script/reprieve/DumpAbiHashes.s.sol:DumpAbiHashes
echo ""

echo "All checks completed."
