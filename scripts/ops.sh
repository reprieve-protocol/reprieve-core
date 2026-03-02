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
  mock-router-deploy <ethereum-sepolia|base-sepolia>
  reprieve-deploy <ethereum-sepolia|base-sepolia>
  full-deploy <ethereum-sepolia|base-sepolia>
  ccip-wire-source <ethereum-sepolia|base-sepolia>
  ccip-wire-dest <ethereum-sepolia|base-sepolia>
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

selector_for_chain_id() {
  local chain_id="$1"
  case "$chain_id" in
    11155111) echo "16015286601757825753" ;; # Ethereum Sepolia selector
    84532) echo "10344971235874465080" ;;    # Base Sepolia selector
    *) echo "" ;;
  esac
}

set_chain() {
  local chain="$1"
  case "$chain" in
    ethereum-sepolia)
      export CHAIN_ID=11155111
      export CHAIN_NAME="Ethereum Sepolia"
      export CONFIG_PATH="$CONTRACTS_DIR/config/ethereum-sepolia.json"
      export OPPOSITE_CHAIN_ID=84532
      export OPPOSITE_CHAIN_NAME="Base Sepolia"
      export OPPOSITE_CONFIG_PATH="$CONTRACTS_DIR/config/base-sepolia.json"
      export RPC_URL="${ETHEREUM_SEPOLIA_RPC:-}"
      export PRIVATE_KEY="${PRIVATE_KEY:-${ETHEREUM_SEPOLIA_DEPLOYER_KEY:-}}"
      export CCIP_ROUTER="${CCIP_ROUTER:-${ETHEREUM_SEPOLIA_CCIP_ROUTER:-}}"
      ;;
    base-sepolia)
      export CHAIN_ID=84532
      export CHAIN_NAME="Base Sepolia"
      export CONFIG_PATH="$CONTRACTS_DIR/config/base-sepolia.json"
      export OPPOSITE_CHAIN_ID=11155111
      export OPPOSITE_CHAIN_NAME="Ethereum Sepolia"
      export OPPOSITE_CONFIG_PATH="$CONTRACTS_DIR/config/ethereum-sepolia.json"
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
  mock-router-deploy)
    set_chain "$chain"
    if [ "$CHAIN_ID" = "11155111" ]; then
      export LINK_TOKEN="${LINK_TOKEN:-${ETHEREUM_SEPOLIA_LINK:-}}"
    else
      export LINK_TOKEN="${LINK_TOKEN:-${BASE_SEPOLIA_LINK:-}}"
    fi
    if [ -z "${LINK_TOKEN:-}" ]; then
      echo "mock-router-deploy requires LINK_TOKEN (or chain-specific ETHEREUM_SEPOLIA_LINK / BASE_SEPOLIA_LINK)."
      exit 1
    fi
    export SOURCE_CHAIN_SELECTOR="${SOURCE_CHAIN_SELECTOR:-$(selector_for_chain_id "$CHAIN_ID")}"
    run_forge_script "script/reprieve/DeployMockCCIPRouter.s.sol:DeployMockCCIPRouter"
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
  ccip-wire-source)
    set_chain "$chain"
    load_lending_addresses_from_config
    load_reprieve_addresses_from_artifact
    opposite_artifact="$CONTRACTS_DIR/config/reprieve-stack-${OPPOSITE_CHAIN_ID}.json"
    opposite_config="$OPPOSITE_CONFIG_PATH"
    export RESCUE_MODE="${RESCUE_MODE:-TOP_UP}"
    export DEST_CHAIN_SELECTOR="${DEST_CHAIN_SELECTOR:-$(selector_for_chain_id "$OPPOSITE_CHAIN_ID")}"
    export SOURCE_CHAIN_SELECTOR="${SOURCE_CHAIN_SELECTOR:-$(selector_for_chain_id "$CHAIN_ID")}"
    export DEST_RECEIVER="${DEST_RECEIVER:-$(json_get_string "$opposite_artifact" "CCIPReceiver")}"
    export MOCK_BRIDGE_SOURCE_TOKEN="${MOCK_BRIDGE_SOURCE_TOKEN:-$COLLATERAL_ASSET}"
    opposite_collateral="$(json_get_string "$opposite_config" "MockERC20_Collateral")"
    opposite_debt="$(json_get_string "$opposite_config" "MockERC20_Debt")"
    if [ "${RESCUE_MODE}" = "REPAY" ]; then
      default_bridge_dest="${opposite_debt:-$MOCK_BRIDGE_SOURCE_TOKEN}"
    else
      default_bridge_dest="${opposite_collateral:-$MOCK_BRIDGE_SOURCE_TOKEN}"
    fi
    export MOCK_BRIDGE_DEST_TOKEN="${MOCK_BRIDGE_DEST_TOKEN:-$default_bridge_dest}"
    if [ -z "${DEST_CHAIN_SELECTOR:-}" ] || [ -z "${DEST_RECEIVER:-}" ]; then
      echo "ccip-wire-source requires DEST_CHAIN_SELECTOR + DEST_RECEIVER (env or opposite-chain artifact)."
      exit 1
    fi
    export LANE_MODE="SOURCE"
    export SOURCE_EXECUTOR="${SOURCE_EXECUTOR:-$RESCUE_EXECUTOR}"
    export SOURCE_ROUTER="${SOURCE_ROUTER:-$CCIP_ROUTER}"
    run_forge_script "script/reprieve/WireCcipLane.s.sol:WireCcipLane"
    ;;
  ccip-wire-dest)
    set_chain "$chain"
    load_reprieve_addresses_from_artifact
    opposite_artifact="$CONTRACTS_DIR/config/reprieve-stack-${OPPOSITE_CHAIN_ID}.json"
    export SOURCE_CHAIN_SELECTOR="${SOURCE_CHAIN_SELECTOR:-$(selector_for_chain_id "$OPPOSITE_CHAIN_ID")}"
    export SOURCE_SENDER="${SOURCE_SENDER:-$(json_get_string "$opposite_artifact" "RescueExecutor")}"
    if [ -z "${SOURCE_CHAIN_SELECTOR:-}" ] || [ -z "${SOURCE_SENDER:-}" ]; then
      echo "ccip-wire-dest requires SOURCE_CHAIN_SELECTOR + SOURCE_SENDER (env or opposite-chain artifact)."
      exit 1
    fi
    export LANE_MODE="DESTINATION"
    export DEST_RECEIVER="${DEST_RECEIVER:-$CCIP_RECEIVER}"
    export DEST_ROUTER="${DEST_ROUTER:-$CCIP_ROUTER}"
    export DEST_EXECUTOR="${DEST_EXECUTOR:-$RESCUE_EXECUTOR}"
    run_forge_script "script/reprieve/WireCcipLane.s.sol:WireCcipLane"
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
    export RESCUE_MODE="${RESCUE_MODE:-TOP_UP}"
    run_forge_script "script/reprieve/RunSameChainRescue.s.sol:RunSameChainRescue"
    ;;
  cross-chain-demo)
    set_chain "$chain"
    load_lending_addresses_from_config
    load_reprieve_addresses_from_artifact
    opposite_artifact="$CONTRACTS_DIR/config/reprieve-stack-${OPPOSITE_CHAIN_ID}.json"
    opposite_config="$OPPOSITE_CONFIG_PATH"
    export RESCUE_MODE="${RESCUE_MODE:-TOP_UP}"

    export SOURCE_CHAIN_SELECTOR="${SOURCE_CHAIN_SELECTOR:-$(selector_for_chain_id "$CHAIN_ID")}"
    export DEST_CHAIN_SELECTOR="${DEST_CHAIN_SELECTOR:-$(selector_for_chain_id "$OPPOSITE_CHAIN_ID")}"
    export DEST_RECEIVER="${DEST_RECEIVER:-$(json_get_string "$opposite_artifact" "CCIPReceiver")}"
    export SOURCE_SENDER="${SOURCE_SENDER:-$RESCUE_EXECUTOR}"

    if [ -z "${DEST_CHAIN_SELECTOR:-}" ] || [ -z "${SOURCE_CHAIN_SELECTOR:-}" ]; then
      echo "Missing SOURCE_CHAIN_SELECTOR or DEST_CHAIN_SELECTOR. Set env or use supported chain."
      exit 1
    fi
    if [ -z "${DEST_RECEIVER:-}" ]; then
      echo "Missing DEST_RECEIVER. Set env or deploy opposite-chain reprieve stack artifact first."
      exit 1
    fi

    export SOURCE_EXECUTOR="${SOURCE_EXECUTOR:-$RESCUE_EXECUTOR}"
    export SOURCE_AAVE_POOL="${SOURCE_AAVE_POOL:-$AAVE_POOL}"
    export SOURCE_AAVE_ADAPTER="${SOURCE_AAVE_ADAPTER:-$AAVE_ADAPTER}"
    export TARGET_ADAPTER="${TARGET_ADAPTER:-$(json_get_string "$opposite_config" "CompoundLikeAdapter")}"
    export TARGET_ADAPTER="${TARGET_ADAPTER:-$COMPOUND_ADAPTER}"
    export DEST_EXECUTOR="${DEST_EXECUTOR:-$(json_get_string "$opposite_artifact" "RescueExecutor")}"
    export MOCK_BRIDGE_SOURCE_TOKEN="${MOCK_BRIDGE_SOURCE_TOKEN:-$COLLATERAL_ASSET}"
    opposite_collateral="$(json_get_string "$opposite_config" "MockERC20_Collateral")"
    opposite_debt="$(json_get_string "$opposite_config" "MockERC20_Debt")"
    if [ "${RESCUE_MODE}" = "REPAY" ]; then
      default_bridge_dest="${opposite_debt:-$MOCK_BRIDGE_SOURCE_TOKEN}"
    else
      default_bridge_dest="${opposite_collateral:-$MOCK_BRIDGE_SOURCE_TOKEN}"
    fi
    export MOCK_BRIDGE_DEST_TOKEN="${MOCK_BRIDGE_DEST_TOKEN:-$default_bridge_dest}"
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
