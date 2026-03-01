#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACTS_DIR="$ROOT_DIR/contracts"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/load-env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/ops.sh <command> [chain]

Commands:
  lending-deploy <ethereum-sepolia|base-sepolia>
  reprieve-deploy <ethereum-sepolia|base-sepolia>
  full-deploy <ethereum-sepolia|base-sepolia>
  reprieve-verify <ethereum-sepolia|base-sepolia>
  same-chain-demo <ethereum-sepolia|base-sepolia>
  cross-chain-demo <ethereum-sepolia|base-sepolia>
  checks
  addresses <ethereum-sepolia|base-sepolia>

Notes:
  - Reads .env and .env.local automatically.
  - For chain deploys, exports PRIVATE_KEY, RPC_URL, CONFIG_PATH automatically.
EOF
}

json_get_string() {
  local file="$1"
  local key="$2"
  if [ ! -f "$file" ]; then
    echo ""
    return
  fi
  sed -nE "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" "$file" | head -n 1
}

set_chain() {
  local chain="$1"
  case "$chain" in
    ethereum-sepolia)
      export CHAIN_ID=11155111
      export CHAIN_NAME="Ethereum Sepolia"
      export CONFIG_PATH="$CONTRACTS_DIR/config/ethereum-sepolia.json"
      export RPC_URL="${ETHEREUM_SEPOLIA_RPC:-}"
      export PRIVATE_KEY="${PRIVATE_KEY:-${ETHEREUM_SEPOLIA_DEPLOYER_KEY:-}}"
      export CCIP_ROUTER="${CCIP_ROUTER:-${ETHEREUM_SEPOLIA_CCIP_ROUTER:-}}"
      ;;
    base-sepolia)
      export CHAIN_ID=84532
      export CHAIN_NAME="Base Sepolia"
      export CONFIG_PATH="$CONTRACTS_DIR/config/base-sepolia.json"
      export RPC_URL="${BASE_SEPOLIA_RPC:-}"
      export PRIVATE_KEY="${PRIVATE_KEY:-${BASE_SEPOLIA_DEPLOYER_KEY:-}}"
      export CCIP_ROUTER="${CCIP_ROUTER:-${BASE_SEPOLIA_CCIP_ROUTER:-}}"
      ;;
    *)
      echo "Unsupported chain: $chain"
      usage
      exit 1
      ;;
  esac

  if [ -z "${RPC_URL:-}" ] || [ -z "${PRIVATE_KEY:-}" ]; then
    echo "Missing chain credentials for $chain. Need RPC + deployer key in .env."
    exit 1
  fi
}

load_lending_addresses_from_config() {
  export COLLATERAL_ASSET="${COLLATERAL_ASSET:-$(json_get_string "$CONFIG_PATH" "MockERC20_Collateral")}"
  export DEBT_ASSET="${DEBT_ASSET:-$(json_get_string "$CONFIG_PATH" "MockERC20_Debt")}"
  export AAVE_POOL="${AAVE_POOL:-$(json_get_string "$CONFIG_PATH" "MockAavePool")}"
  export COMPOUND_MARKET="${COMPOUND_MARKET:-$(json_get_string "$CONFIG_PATH" "MockCompoundComet")}"
  export MORPHO_MARKET="${MORPHO_MARKET:-$(json_get_string "$CONFIG_PATH" "MockMorphoMarket")}"
  export AAVE_ADAPTER="${AAVE_ADAPTER:-$(json_get_string "$CONFIG_PATH" "AaveLikeAdapter")}"
  export COMPOUND_ADAPTER="${COMPOUND_ADAPTER:-$(json_get_string "$CONFIG_PATH" "CompoundLikeAdapter")}"
  export MORPHO_ADAPTER="${MORPHO_ADAPTER:-$(json_get_string "$CONFIG_PATH" "MorphoLikeAdapter")}"
}

load_reprieve_addresses_from_artifact() {
  local artifact="$CONTRACTS_DIR/config/reprieve-stack-${CHAIN_ID}.json"
  export ADAPTER_REGISTRY="${ADAPTER_REGISTRY:-$(json_get_string "$artifact" "AdapterRegistry")}"
  export RESCUE_LOG="${RESCUE_LOG:-$(json_get_string "$artifact" "RescueLog")}"
  export RESCUE_ESCROW="${RESCUE_ESCROW:-$(json_get_string "$artifact" "RescueEscrow")}"
  export RESCUE_EXECUTOR="${RESCUE_EXECUTOR:-$(json_get_string "$artifact" "RescueExecutor")}"
  export CCIP_RECEIVER="${CCIP_RECEIVER:-$(json_get_string "$artifact" "CCIPReceiver")}"
  export HEALTH_MONITOR="${HEALTH_MONITOR:-$(json_get_string "$artifact" "HealthMonitor")}"
}

run_forge_script() {
  local target="$1"
  cd "$CONTRACTS_DIR"
  forge script "$target" --rpc-url "$RPC_URL" --broadcast -vvvv
}

cmd="${1:-}"
chain="${2:-}"

case "$cmd" in
  lending-deploy)
    set_chain "$chain"
    echo "Deploying lending stack on $CHAIN_NAME..."
    run_forge_script "script/demo/DeployLendingStack.s.sol:DeployLendingStack"
    ;;
  reprieve-deploy)
    set_chain "$chain"
    load_lending_addresses_from_config
    echo "Deploying reprieve stack on $CHAIN_NAME..."
    run_forge_script "script/reprieve/DeployReprieveStack.s.sol:DeployReprieveStack"
    ;;
  full-deploy)
    set_chain "$chain"
    echo "Deploying lending stack on $CHAIN_NAME..."
    run_forge_script "script/demo/DeployLendingStack.s.sol:DeployLendingStack"
    load_lending_addresses_from_config
    echo "Deploying reprieve stack on $CHAIN_NAME..."
    run_forge_script "script/reprieve/DeployReprieveStack.s.sol:DeployReprieveStack"
    ;;
  reprieve-verify)
    set_chain "$chain"
    load_lending_addresses_from_config
    load_reprieve_addresses_from_artifact
    run_forge_script "script/reprieve/VerifyReprieveStack.s.sol:VerifyReprieveStack"
    ;;
  same-chain-demo)
    set_chain "$chain"
    load_lending_addresses_from_config
    load_reprieve_addresses_from_artifact
    run_forge_script "script/reprieve/RunSameChainRescue.s.sol:RunSameChainRescue"
    ;;
  cross-chain-demo)
    set_chain "$chain"
    load_lending_addresses_from_config
    load_reprieve_addresses_from_artifact
    if [ -z "${DEST_CHAIN_SELECTOR:-}" ] || [ -z "${SOURCE_CHAIN_SELECTOR:-}" ]; then
      echo "Missing SOURCE_CHAIN_SELECTOR or DEST_CHAIN_SELECTOR. Set both in .env for CCIP runs."
      exit 1
    fi
    export SOURCE_EXECUTOR="${SOURCE_EXECUTOR:-$RESCUE_EXECUTOR}"
    export SOURCE_AAVE_POOL="${SOURCE_AAVE_POOL:-$AAVE_POOL}"
    export SOURCE_AAVE_ADAPTER="${SOURCE_AAVE_ADAPTER:-$AAVE_ADAPTER}"
    export TARGET_ADAPTER="${TARGET_ADAPTER:-$COMPOUND_ADAPTER}"
    export DEST_RECEIVER="${DEST_RECEIVER:-$CCIP_RECEIVER}"
    run_forge_script "script/reprieve/RunCrossChainRescue.s.sol:RunCrossChainRescue"
    ;;
  checks)
    cd "$ROOT_DIR"
    "$ROOT_DIR/scripts/reprieve/run-all-checks.sh"
    ;;
  addresses)
    set_chain "$chain"
    load_lending_addresses_from_config
    load_reprieve_addresses_from_artifact
    cd "$ROOT_DIR"
    "$ROOT_DIR/scripts/reprieve/print-addresses.sh"
    ;;
  *)
    usage
    exit 1
    ;;
esac
