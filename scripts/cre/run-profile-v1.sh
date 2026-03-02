#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="${1:-staging-settings}"

cd "$ROOT/cre"
printf '3\n' | cre workflow simulate ./reprieve-chainlink-api-guard-v1 --target="$TARGET"
