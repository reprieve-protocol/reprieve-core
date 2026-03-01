#!/bin/bash
set -euo pipefail

# shellcheck disable=SC2034
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
ENV_LOCAL_FILE="${ENV_LOCAL_FILE:-$ROOT_DIR/.env.local}"

load_env_file() {
  local file="$1"
  if [ -f "$file" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$file"
    set +a
    echo "Loaded env: $file"
  fi
}

load_env_file "$ENV_FILE"
load_env_file "$ENV_LOCAL_FILE"
