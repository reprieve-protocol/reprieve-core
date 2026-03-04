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
  set-oracle-price <ethereum-sepolia|base-sepolia> <symbol> <price-usd>
  set-oracle-price-both <chain-a> <chain-b> <symbol> <price-usd>
  approve-aave-receipt <ethereum-sepolia|base-sepolia>
  deposit-collateral <ethereum-sepolia|base-sepolia> <symbol> <AAVE|COMPOUND|MORPHO> <amount>
  withdraw-collateral <ethereum-sepolia|base-sepolia> <symbol> <AAVE|COMPOUND|MORPHO> <amount>
  borrow-asset <ethereum-sepolia|base-sepolia> <symbol> <AAVE|COMPOUND|MORPHO> <amount>
  repay-asset <ethereum-sepolia|base-sepolia> <symbol> <AAVE|COMPOUND|MORPHO> <amount>
  mock-router-deploy <ethereum-sepolia|base-sepolia>
  mock-fee-set <ethereum-sepolia|base-sepolia> <ethereum-sepolia|base-sepolia|dest-selector> <fee-eth>
  ccip-mapping-check <ethereum-sepolia|base-sepolia> <ethereum-sepolia|base-sepolia|dest-selector> <source-symbol|source-token-address>
  bridge-role-check <ethereum-sepolia|base-sepolia> <token-address> <account-address>
  bridge-role-set <ethereum-sepolia|base-sepolia> <token-address> <account-address> <minter|burner|both> [true|false]
  mock-relay <source-chain> <destination-chain> [message-id|latest]
  cross-chain-rescue-setup-source <ethereum-sepolia|base-sepolia>
  cross-chain-rescue-setup-destination <ethereum-sepolia|base-sepolia>
  cross-chain-rescue-execute <ethereum-sepolia|base-sepolia>
  cross-chain-rescue-relay <source-chain> <destination-chain> [message-id|latest]
  same-chain-rescue-setup <ethereum-sepolia|base-sepolia>
  reprieve-deploy <ethereum-sepolia|base-sepolia>
  workflow-receiver-deploy <ethereum-sepolia|base-sepolia>
  workflow-receiver-wire <ethereum-sepolia|base-sepolia>
  workflow-receiver-debug-onreport <ethereum-sepolia|base-sepolia> <calldata-hex>
  decode-onreport <calldata-hex>
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
  - set-oracle-price examples: `./scripts/ops.sh set-oracle-price ethereum-sepolia WETH 1850.25`
  - set-oracle-price-both example: `./scripts/ops.sh set-oracle-price-both ethereum-sepolia base-sepolia WETH 1850.25`
  - user action examples:
    - `./scripts/ops.sh approve-aave-receipt ethereum-sepolia`
    - `./scripts/ops.sh deposit-collateral ethereum-sepolia WETH AAVE 1.5`
    - `./scripts/ops.sh borrow-asset ethereum-sepolia USDC COMPOUND 2500`
  - mock fee example:
    - `./scripts/ops.sh mock-fee-set ethereum-sepolia base-sepolia 0`
    - `./scripts/ops.sh mock-fee-set base-sepolia 16015286601757825753 0.005`
  - mapping check example:
    - `./scripts/ops.sh ccip-mapping-check ethereum-sepolia base-sepolia WETH`
    - `./scripts/ops.sh ccip-mapping-check ethereum-sepolia 10344971235874465080 0x4c87EA388AdE37f6A556146B4fF6ff2A12192968`
  - bridge role examples:
    - `./scripts/ops.sh bridge-role-check base-sepolia 0x7570... 0xAE39...`
    - `./scripts/ops.sh bridge-role-set base-sepolia 0x7570... 0xAE39... minter true`
    - `./scripts/ops.sh bridge-role-set base-sepolia 0x7570... 0xAE39... burner true`
    - `./scripts/ops.sh bridge-role-set base-sepolia 0x7570... 0xAE39... both true`
  - workflow receiver deploy:
    - `CRE_FORWARDER=0x... ./scripts/ops.sh workflow-receiver-deploy ethereum-sepolia`
  - workflow receiver wire:
    - `WF_EXPECTED_AUTHOR=0x... ./scripts/ops.sh workflow-receiver-wire ethereum-sepolia`
  - workflow receiver debug:
    - `./scripts/ops.sh workflow-receiver-debug-onreport ethereum-sepolia 0x805f2132...`
    - Optional: `BROADCAST_DEBUG=true FAIL_ON_REVERT=true ./scripts/ops.sh workflow-receiver-debug-onreport ethereum-sepolia 0x805f2132...`
  - decode onReport calldata:
    - `./scripts/ops.sh decode-onreport 0x805f2132...`
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

json_get_path_string() {
  local file="$1"
  local path="$2"
  if [ ! -f "$file" ]; then
    echo ""
    return
  fi
  jq -r "$path // empty" "$file" 2>/dev/null
}

to_upper() {
  echo "$1" | tr '[:lower:]' '[:upper:]'
}

to_wad_18() {
  local human="$1"
  if [[ ! "$human" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "Invalid price '$human'. Use unsigned decimal format, e.g. 2000 or 2000.25" >&2
    return 1
  fi

  local whole="${human%%.*}"
  local frac=""
  if [[ "$human" == *.* ]]; then
    frac="${human#*.}"
  fi
  if [ "${#frac}" -gt 18 ]; then
    echo "Invalid price '$human'. Maximum supported precision is 18 decimals." >&2
    return 1
  fi

  while [ "${#frac}" -lt 18 ]; do
    frac="${frac}0"
  done

  local wad="${whole}${frac}"
  wad="$(echo "$wad" | sed -E 's/^0+//')"
  if [ -z "$wad" ]; then
    wad="0"
  fi
  echo "$wad"
}

print_asset_map() {
  local collateral_symbol debt_symbol
  collateral_symbol="$(to_upper "$(json_get_path_string "$CONFIG_PATH" '.tokenParams.collateral.symbol')")"
  debt_symbol="$(to_upper "$(json_get_path_string "$CONFIG_PATH" '.tokenParams.debt.symbol')")"

  echo "Asset map for $CHAIN_NAME:"
  echo "  ${collateral_symbol:-COLLATERAL} -> ${COLLATERAL_ASSET:-<missing>}"
  if [ "${collateral_symbol:-}" = "WETH" ]; then
    echo "  ETH -> ${COLLATERAL_ASSET:-<missing>} (alias)"
  fi
  echo "  ${debt_symbol:-DEBT} -> ${DEBT_ASSET:-<missing>}"
  echo "  COLLATERAL -> ${COLLATERAL_ASSET:-<missing>} (alias)"
  echo "  DEBT -> ${DEBT_ASSET:-<missing>} (alias)"
}

resolve_asset_by_symbol() {
  local input_symbol="$1"
  local symbol
  symbol="$(to_upper "$input_symbol")"

  local collateral_symbol debt_symbol
  collateral_symbol="$(to_upper "$(json_get_path_string "$CONFIG_PATH" '.tokenParams.collateral.symbol')")"
  debt_symbol="$(to_upper "$(json_get_path_string "$CONFIG_PATH" '.tokenParams.debt.symbol')")"

  if [ -n "${collateral_symbol:-}" ] && [ "$symbol" = "$collateral_symbol" ]; then
    echo "${collateral_symbol}|${COLLATERAL_ASSET}"
    return
  fi
  if [ "$symbol" = "COLLATERAL" ]; then
    echo "${collateral_symbol:-COLLATERAL}|${COLLATERAL_ASSET}"
    return
  fi
  if [ "$symbol" = "ETH" ] && [ "${collateral_symbol:-}" = "WETH" ]; then
    echo "WETH|${COLLATERAL_ASSET}"
    return
  fi

  if [ -n "${debt_symbol:-}" ] && [ "$symbol" = "$debt_symbol" ]; then
    echo "${debt_symbol}|${DEBT_ASSET}"
    return
  fi
  if [ "$symbol" = "DEBT" ]; then
    echo "${debt_symbol:-DEBT}|${DEBT_ASSET}"
    return
  fi

  echo ""
}

normalize_protocol() {
  local input="$1"
  local p
  p="$(to_upper "$input")"
  case "$p" in
    AAVE|COMPOUND|MORPHO) echo "$p" ;;
    *) echo "" ;;
  esac
}

protocol_market_address() {
  local protocol="$1"
  case "$protocol" in
    AAVE) echo "${AAVE_POOL:-}" ;;
    COMPOUND) echo "${COMPOUND_MARKET:-}" ;;
    MORPHO) echo "${MORPHO_MARKET:-}" ;;
    *) echo "" ;;
  esac
}

protocol_adapter_address() {
  local protocol="$1"
  case "$protocol" in
    AAVE) echo "${AAVE_ADAPTER:-}" ;;
    COMPOUND) echo "${COMPOUND_ADAPTER:-}" ;;
    MORPHO) echo "${MORPHO_ADAPTER:-}" ;;
    *) echo "" ;;
  esac
}

asset_decimals_by_address() {
  local asset="$1"
  local asset_lc collateral_lc debt_lc
  asset_lc="$(echo "$asset" | tr '[:upper:]' '[:lower:]')"
  collateral_lc="$(echo "${COLLATERAL_ASSET:-}" | tr '[:upper:]' '[:lower:]')"
  debt_lc="$(echo "${DEBT_ASSET:-}" | tr '[:upper:]' '[:lower:]')"

  local collateral_decimals debt_decimals
  collateral_decimals="$(json_get_path_string "$CONFIG_PATH" '.tokenParams.collateral.decimals')"
  debt_decimals="$(json_get_path_string "$CONFIG_PATH" '.tokenParams.debt.decimals')"

  if [ "$asset_lc" = "$collateral_lc" ] && [ -n "${collateral_decimals:-}" ]; then
    echo "$collateral_decimals"
    return
  fi
  if [ "$asset_lc" = "$debt_lc" ] && [ -n "${debt_decimals:-}" ]; then
    echo "$debt_decimals"
    return
  fi
  echo "18"
}

to_token_units() {
  local human="$1"
  local decimals="$2"
  if [[ ! "$decimals" =~ ^[0-9]+$ ]]; then
    echo "Invalid decimals '$decimals'." >&2
    return 1
  fi
  if [[ ! "$human" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "Invalid amount '$human'. Use unsigned decimal format, e.g. 1 or 1.25" >&2
    return 1
  fi

  local whole="${human%%.*}"
  local frac=""
  if [[ "$human" == *.* ]]; then
    frac="${human#*.}"
  fi
  if [ "${#frac}" -gt "$decimals" ]; then
    echo "Invalid amount '$human'. Maximum precision for this token is $decimals decimals." >&2
    return 1
  fi

  while [ "${#frac}" -lt "$decimals" ]; do
    frac="${frac}0"
  done

  local units="${whole}${frac}"
  units="$(echo "$units" | sed -E 's/^0+//')"
  if [ -z "$units" ]; then
    units="0"
  fi
  echo "$units"
}

prepare_user_action_env() {
  local symbol_input="$1"
  local protocol_input="$2"
  local amount_human="$3"

  local resolved normalized_protocol market adapter
  resolved="$(resolve_asset_by_symbol "$symbol_input")"
  if [ -z "$resolved" ]; then
    echo "Unsupported symbol '$symbol_input' for $CHAIN_NAME."
    print_asset_map
    return 1
  fi

  normalized_protocol="$(normalize_protocol "$protocol_input")"
  if [ -z "$normalized_protocol" ]; then
    echo "Unsupported protocol '$protocol_input'. Use AAVE, COMPOUND, or MORPHO."
    return 1
  fi

  market="$(protocol_market_address "$normalized_protocol")"
  if [ -z "$market" ]; then
    echo "Missing market address for protocol '$normalized_protocol' on $CHAIN_NAME."
    return 1
  fi

  adapter="$(protocol_adapter_address "$normalized_protocol")"
  if [ -z "$adapter" ]; then
    echo "Missing adapter address for protocol '$normalized_protocol' on $CHAIN_NAME."
    return 1
  fi

  local resolved_symbol resolved_asset decimals amount_raw
  resolved_symbol="${resolved%%|*}"
  resolved_asset="${resolved#*|}"
  decimals="$(asset_decimals_by_address "$resolved_asset")"
  amount_raw="$(to_token_units "$amount_human" "$decimals")"
  if [ -z "$amount_raw" ] || [ "$amount_raw" = "0" ]; then
    echo "Invalid amount '$amount_human' (must resolve to non-zero token units)."
    return 1
  fi

  export ASSET_SYMBOL="$resolved_symbol"
  export ASSET_ADDRESS="$resolved_asset"
  export ASSET_DECIMALS="$decimals"
  export AMOUNT_HUMAN="$amount_human"
  export AMOUNT_RAW="$amount_raw"
  export PROTOCOL_KIND="$normalized_protocol"
  export MARKET_ADDRESS="$market"
  export ADAPTER_ADDRESS="$adapter"

  return 0
}

selector_for_chain_id() {
  local chain_id="$1"
  case "$chain_id" in
    11155111) echo "16015286601757825753" ;; # Ethereum Sepolia selector
    84532) echo "10344971235874465080" ;;    # Base Sepolia selector
    *) echo "" ;;
  esac
}

resolve_selector() {
  local input="$1"
  if [[ "$input" =~ ^[0-9]+$ ]]; then
    echo "$input"
    return
  fi

  case "$input" in
    ethereum-sepolia)
      echo "16015286601757825753"
      ;;
    base-sepolia)
      echo "10344971235874465080"
      ;;
    *)
      echo ""
      ;;
  esac
}

resolve_latest_mock_message_id() {
  local chain_id="$1"
  local broadcast_file="$CONTRACTS_DIR/broadcast/CrossChainRescueExecute.s.sol/${chain_id}/run-latest.json"
  local message_sent_topic0="0x6d5ba46f25f47bd5afde9be3a22d0edab6520e9398be746f60677eb206032f41"
  if [ ! -f "$broadcast_file" ]; then
    echo ""
    return
  fi
  jq -r --arg t0 "$message_sent_topic0" '
    [
      .receipts[]?.logs[]?
      | select((.topics[0] | ascii_downcase) == ($t0 | ascii_downcase))
      | .topics[1]
    ] | last // empty
  ' "$broadcast_file"
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

load_workflow_receiver_from_artifact() {
  local artifact="$CONTRACTS_DIR/config/reprieve-workflow-receiver-${CHAIN_ID}.json"
  export WORKFLOW_RECEIVER="${WORKFLOW_RECEIVER:-$(json_get_string "$artifact" "WorkflowReceiver")}"
}

resolve_cre_forwarder() {
  if [ -n "${CRE_FORWARDER:-}" ]; then
    return
  fi

  case "${CHAIN_ID:-}" in
    11155111)
      export CRE_FORWARDER="${ETHEREUM_SEPOLIA_CRE_FORWARDER:-}"
      ;;
    84532)
      export CRE_FORWARDER="${BASE_SEPOLIA_CRE_FORWARDER:-}"
      ;;
  esac
}

run_forge_script() {
  local target="$1"
  cd "$CONTRACTS_DIR"
  forge script "$target" --rpc-url "$RPC_URL" --broadcast -vvvv
}

run_forge_script_readonly() {
  local target="$1"
  cd "$CONTRACTS_DIR"
  forge script "$target" --rpc-url "$RPC_URL" -vvvv
}

run_forge_script_local() {
  local target="$1"
  cd "$CONTRACTS_DIR"
  forge script "$target" -vvvv
}

cmd="${1:-}"
arg2="${2:-}"
arg3="${3:-}"
arg4="${4:-}"
arg5="${5:-}"
chain="$arg2"

case "$cmd" in
  decode-onreport)
    calldata_hex="$arg2"
    if [ -z "$calldata_hex" ]; then
      echo "decode-onreport requires <calldata-hex>"
      usage
      exit 1
    fi
    export ONREPORT_CALLDATA="$calldata_hex"
    echo "Decoding onReport calldata..."
    run_forge_script_local "script/reprieve/DecodeOnReportCalldata.s.sol:DecodeOnReportCalldata"
    ;;
  lending-deploy)
    set_chain "$chain"
    echo "Deploying lending stack on $CHAIN_NAME..."
    run_forge_script "script/demo/DeployLendingStack.s.sol:DeployLendingStack"
    ;;
  set-oracle-price)
    set_chain "$chain"
    symbol="${arg3:-}"
    human_price="${arg4:-}"
    if [ -z "$symbol" ] || [ -z "$human_price" ]; then
      echo "set-oracle-price requires <chain> <symbol> <price-usd>"
      usage
      exit 1
    fi

    load_lending_addresses_from_config
    oracle_from_config="$(json_get_path_string "$CONFIG_PATH" '.contracts.MockPriceOracle')"
    export PRICE_ORACLE="${PRICE_ORACLE:-$oracle_from_config}"
    if [ -z "${PRICE_ORACLE:-}" ]; then
      echo "Missing PRICE_ORACLE and no .contracts.MockPriceOracle in $CONFIG_PATH"
      exit 1
    fi

    resolved="$(resolve_asset_by_symbol "$symbol")"
    if [ -z "$resolved" ]; then
      echo "Unsupported symbol '$symbol' for $CHAIN_NAME."
      print_asset_map
      exit 1
    fi

    resolved_symbol="${resolved%%|*}"
    resolved_asset="${resolved#*|}"
    if [ -z "$resolved_asset" ]; then
      echo "Resolved empty asset address for symbol '$symbol'."
      exit 1
    fi

    price_wad="$(to_wad_18 "$human_price")"
    if [ -z "$price_wad" ] || [ "$price_wad" = "0" ]; then
      echo "Invalid price '$human_price' (must resolve to non-zero wad)."
      exit 1
    fi

    export ASSET_SYMBOL="$resolved_symbol"
    export ASSET_ADDRESS="$resolved_asset"
    export PRICE_HUMAN="$human_price"
    export PRICE_WAD="$price_wad"

    echo "Setting oracle price on $CHAIN_NAME"
    echo "  Oracle: $PRICE_ORACLE"
    echo "  Symbol: $ASSET_SYMBOL"
    echo "  Asset : $ASSET_ADDRESS"
    echo "  Price : $PRICE_HUMAN USD"
    echo "  WAD   : $PRICE_WAD"
    run_forge_script "script/demo/SetOraclePrice.s.sol:SetOraclePrice"
    ;;
  set-oracle-price-both)
    chain_a="${arg2:-}"
    chain_b="${arg3:-}"
    symbol="${arg4:-}"
    human_price="${arg5:-}"
    if [ -z "$chain_a" ] || [ -z "$chain_b" ] || [ -z "$symbol" ] || [ -z "$human_price" ]; then
      echo "set-oracle-price-both requires <chain-a> <chain-b> <symbol> <price-usd>"
      usage
      exit 1
    fi

    echo "Setting ${symbol}=${human_price} on ${chain_a}..."
    "$ROOT_DIR/scripts/ops.sh" set-oracle-price "$chain_a" "$symbol" "$human_price"
    echo "Setting ${symbol}=${human_price} on ${chain_b}..."
    "$ROOT_DIR/scripts/ops.sh" set-oracle-price "$chain_b" "$symbol" "$human_price"
    echo "Done: ${symbol}=${human_price} updated on ${chain_a} and ${chain_b}."
    ;;
  approve-aave-receipt)
    set_chain "$chain"
    load_lending_addresses_from_config
    if [ -z "${AAVE_POOL:-}" ] || [ -z "${AAVE_ADAPTER:-}" ]; then
      echo "approve-aave-receipt requires AAVE_POOL and AAVE_ADAPTER in config/env."
      exit 1
    fi
    echo "Approving Aave receipt token allowance on $CHAIN_NAME"
    echo "  Aave Pool: $AAVE_POOL"
    echo "  Adapter  : $AAVE_ADAPTER"
    run_forge_script "script/demo/ApproveAaveReceiptToken.s.sol:ApproveAaveReceiptToken"
    ;;
  deposit-collateral)
    set_chain "$chain"
    symbol="${arg3:-}"
    protocol="${arg4:-}"
    amount="${arg5:-}"
    if [ -z "$symbol" ] || [ -z "$protocol" ] || [ -z "$amount" ]; then
      echo "deposit-collateral requires <chain> <symbol> <protocol> <amount>"
      usage
      exit 1
    fi
    load_lending_addresses_from_config
    prepare_user_action_env "$symbol" "$protocol" "$amount"
    echo "Depositing collateral on $CHAIN_NAME"
    echo "  Protocol: $PROTOCOL_KIND"
    echo "  Adapter : $ADAPTER_ADDRESS"
    echo "  Market  : $MARKET_ADDRESS"
    echo "  Asset   : $ASSET_SYMBOL ($ASSET_ADDRESS)"
    echo "  Amount  : $AMOUNT_HUMAN (raw=$AMOUNT_RAW)"
    run_forge_script "script/demo/DepositCollateral.s.sol:DepositCollateral"
    ;;
  withdraw-collateral)
    set_chain "$chain"
    symbol="${arg3:-}"
    protocol="${arg4:-}"
    amount="${arg5:-}"
    if [ -z "$symbol" ] || [ -z "$protocol" ] || [ -z "$amount" ]; then
      echo "withdraw-collateral requires <chain> <symbol> <protocol> <amount>"
      usage
      exit 1
    fi
    load_lending_addresses_from_config
    prepare_user_action_env "$symbol" "$protocol" "$amount"
    echo "Withdrawing collateral on $CHAIN_NAME"
    echo "  Protocol: $PROTOCOL_KIND"
    echo "  Adapter : $ADAPTER_ADDRESS"
    echo "  Market  : $MARKET_ADDRESS"
    echo "  Asset   : $ASSET_SYMBOL ($ASSET_ADDRESS)"
    echo "  Amount  : $AMOUNT_HUMAN (raw=$AMOUNT_RAW)"
    run_forge_script "script/demo/WithdrawCollateral.s.sol:WithdrawCollateral"
    ;;
  borrow-asset)
    set_chain "$chain"
    symbol="${arg3:-}"
    protocol="${arg4:-}"
    amount="${arg5:-}"
    if [ -z "$symbol" ] || [ -z "$protocol" ] || [ -z "$amount" ]; then
      echo "borrow-asset requires <chain> <symbol> <protocol> <amount>"
      usage
      exit 1
    fi
    load_lending_addresses_from_config
    prepare_user_action_env "$symbol" "$protocol" "$amount"
    echo "Borrowing asset on $CHAIN_NAME"
    echo "  Protocol: $PROTOCOL_KIND"
    echo "  Adapter : $ADAPTER_ADDRESS"
    echo "  Market  : $MARKET_ADDRESS"
    echo "  Asset   : $ASSET_SYMBOL ($ASSET_ADDRESS)"
    echo "  Amount  : $AMOUNT_HUMAN (raw=$AMOUNT_RAW)"
    run_forge_script "script/demo/BorrowAsset.s.sol:BorrowAsset"
    ;;
  repay-asset)
    set_chain "$chain"
    symbol="${arg3:-}"
    protocol="${arg4:-}"
    amount="${arg5:-}"
    if [ -z "$symbol" ] || [ -z "$protocol" ] || [ -z "$amount" ]; then
      echo "repay-asset requires <chain> <symbol> <protocol> <amount>"
      usage
      exit 1
    fi
    load_lending_addresses_from_config
    prepare_user_action_env "$symbol" "$protocol" "$amount"
    echo "Repaying asset on $CHAIN_NAME"
    echo "  Protocol: $PROTOCOL_KIND"
    echo "  Adapter : $ADAPTER_ADDRESS"
    echo "  Market  : $MARKET_ADDRESS"
    echo "  Asset   : $ASSET_SYMBOL ($ASSET_ADDRESS)"
    echo "  Amount  : $AMOUNT_HUMAN (raw=$AMOUNT_RAW)"
    run_forge_script "script/demo/RepayAsset.s.sol:RepayAsset"
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
  mock-fee-set)
    set_chain "$chain"
    dest_input="${arg3:-}"
    fee_human="${arg4:-}"
    if [ -z "$dest_input" ] || [ -z "$fee_human" ]; then
      echo "mock-fee-set requires <chain> <dest-chain|dest-selector> <fee-eth>."
      usage
      exit 1
    fi
    if [ -z "${CCIP_ROUTER:-}" ]; then
      echo "Missing CCIP_ROUTER for $CHAIN_NAME (set chain router env first)."
      exit 1
    fi

    dest_selector="$(resolve_selector "$dest_input")"
    if [ -z "$dest_selector" ]; then
      echo "Unsupported destination '$dest_input'. Use base-sepolia, ethereum-sepolia, or numeric selector."
      exit 1
    fi

    fee_wei="$(to_token_units "$fee_human" 18)"
    if [ -z "$fee_wei" ]; then
      echo "Invalid fee '$fee_human'."
      exit 1
    fi

    export DEST_CHAIN_SELECTOR="$dest_selector"
    export MOCK_FEE_WEI="$fee_wei"

    echo "Setting mock CCIP fee on $CHAIN_NAME"
    echo "  Router           : $CCIP_ROUTER"
    echo "  Destination input: $dest_input"
    echo "  Destination sel  : $DEST_CHAIN_SELECTOR"
    echo "  Fee (ETH)        : $fee_human"
    echo "  Fee (wei)        : $MOCK_FEE_WEI"
    run_forge_script "script/reprieve/SetMockCcipFee.s.sol:SetMockCcipFee"
    ;;
  ccip-mapping-check)
    set_chain "$chain"
    load_lending_addresses_from_config

    dest_input="${arg3:-}"
    source_token_input="${arg4:-}"
    if [ -z "$dest_input" ] || [ -z "$source_token_input" ]; then
      echo "ccip-mapping-check requires <source-chain> <dest-chain|selector> <source-symbol|source-token-address>."
      usage
      exit 1
    fi

    dest_selector="$(resolve_selector "$dest_input")"
    if [ -z "$dest_selector" ]; then
      echo "Unsupported destination selector input '$dest_input'. Use chain name or numeric selector."
      exit 1
    fi

    source_resolved="$(resolve_asset_by_symbol "$source_token_input")"
    source_symbol=""
    source_token_addr=""
    if [ -n "$source_resolved" ]; then
      source_symbol="${source_resolved%%|*}"
      source_token_addr="${source_resolved#*|}"
    elif [[ "$source_token_input" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
      source_symbol="RAW"
      source_token_addr="$source_token_input"
    else
      echo "Unsupported source token '$source_token_input' for $CHAIN_NAME."
      echo "Pass symbol from asset map (e.g. WETH/USDC) or a token address."
      print_asset_map
      exit 1
    fi

    export SOURCE_ROUTER="${SOURCE_ROUTER:-$CCIP_ROUTER}"
    export DEST_CHAIN_SELECTOR="$dest_selector"
    export SOURCE_TOKEN="$source_token_addr"
    export SOURCE_TOKEN_SYMBOL="$source_symbol"

    if [ -z "${SOURCE_ROUTER:-}" ]; then
      echo "Missing SOURCE_ROUTER/CCIP_ROUTER for $CHAIN_NAME."
      exit 1
    fi

    echo "Checking CCIP token mapping on $CHAIN_NAME"
    echo "  Source router     : $SOURCE_ROUTER"
    echo "  Destination input : $dest_input"
    echo "  Destination sel   : $DEST_CHAIN_SELECTOR"
    echo "  Source token input: $source_token_input"
    echo "  Source token addr : $SOURCE_TOKEN"
    run_forge_script_readonly "script/reprieve/CheckMockTokenMapping.s.sol:CheckMockTokenMapping"
    ;;
  bridge-role-check)
    set_chain "$chain"
    token_addr="${arg3:-}"
    bridge_account="${arg4:-}"
    if [ -z "$token_addr" ] || [ -z "$bridge_account" ]; then
      echo "bridge-role-check requires <chain> <token-address> <account-address>."
      usage
      exit 1
    fi
    export TOKEN_ADDRESS="$token_addr"
    export BRIDGE_ACCOUNT="$bridge_account"
    echo "Checking bridge roles on $CHAIN_NAME"
    echo "  Token         : $TOKEN_ADDRESS"
    echo "  Bridge account: $BRIDGE_ACCOUNT"
    run_forge_script_readonly "script/reprieve/CheckBridgeRoles.s.sol:CheckBridgeRoles"
    ;;
  bridge-role-set)
    set_chain "$chain"
    token_addr="${arg3:-}"
    bridge_account="${arg4:-}"
    role_kind_input="${arg5:-}"
    allowed_input="${6:-true}"
    if [ -z "$token_addr" ] || [ -z "$bridge_account" ] || [ -z "$role_kind_input" ]; then
      echo "bridge-role-set requires <chain> <token-address> <account-address> <minter|burner|both> [true|false]."
      usage
      exit 1
    fi

    role_kind="$(to_upper "$role_kind_input")"
    case "$role_kind" in
      MINTER|BURNER|BOTH) ;;
      *)
        echo "Invalid role kind '$role_kind_input'. Use minter, burner, or both."
        exit 1
        ;;
    esac

    allowed_lower="$(echo "$allowed_input" | tr '[:upper:]' '[:lower:]')"
    case "$allowed_lower" in
      true|false) ;;
      *)
        echo "Invalid allowed flag '$allowed_input'. Use true or false."
        exit 1
        ;;
    esac

    export TOKEN_ADDRESS="$token_addr"
    export BRIDGE_ACCOUNT="$bridge_account"
    export ROLE_KIND="$role_kind"
    if [ "$allowed_lower" = "true" ]; then
      export ROLE_ALLOWED=true
    else
      export ROLE_ALLOWED=false
    fi

    echo "Setting bridge roles on $CHAIN_NAME"
    echo "  Token         : $TOKEN_ADDRESS"
    echo "  Bridge account: $BRIDGE_ACCOUNT"
    echo "  Role kind     : $ROLE_KIND"
    echo "  Allowed       : $ROLE_ALLOWED"
    run_forge_script "script/reprieve/SetBridgeRoles.s.sol:SetBridgeRoles"
    ;;
  mock-relay|cross-chain-rescue-relay)
    source_chain="$arg2"
    dest_chain="$arg3"
    message_id="${arg4:-latest}"
    if [ -z "$source_chain" ] || [ -z "$dest_chain" ]; then
      echo "mock-relay requires <source-chain> <destination-chain> [message-id|latest]."
      usage
      exit 1
    fi

    unset RPC_URL
    unset PRIVATE_KEY
    unset CCIP_ROUTER
    set_chain "$source_chain"
    source_chain_id="$CHAIN_ID"
    source_selector="$(selector_for_chain_id "$CHAIN_ID")"
    source_router="$CCIP_ROUTER"
    if [ -z "${source_router:-}" ]; then
      echo "Missing source CCIP router for $source_chain (set chain router env first)."
      exit 1
    fi
    if [ "$message_id" = "latest" ]; then
      message_id="$(resolve_latest_mock_message_id "$source_chain_id")"
      if [ -z "$message_id" ] || [ "$message_id" = "null" ]; then
        echo "Could not resolve latest message id from source broadcast artifact."
        echo "Run cross-chain-rescue-execute first or pass an explicit <message-id>."
        exit 1
      fi
      echo "Resolved latest source message id: $message_id"
    fi

    export_file="$CONTRACTS_DIR/config/mock-relay-${source_chain_id}.env"
    export MOCK_CCIP_ROUTER="$source_router"
    export MOCK_MESSAGE_ID="$message_id"
    export MOCK_EXPORT_PATH="$export_file"

    echo "Exporting source mock message from $source_chain..."
    run_forge_script_readonly "script/reprieve/ExportMockCCIPMessage.s.sol:ExportMockCCIPMessage"

    if [ ! -f "$export_file" ]; then
      echo "Failed to export source message file: $export_file"
      exit 1
    fi
    # shellcheck disable=SC1090
    set -a
    source "$export_file"
    set +a
    if [ -z "${MOCK_SOURCE_SELECTOR:-}" ] || [ -z "${MOCK_DEST_RECEIVER:-}" ] || [ -z "${MOCK_PAYLOAD:-}" ]; then
      echo "Export file missing required relay fields."
      exit 1
    fi
    if [ -n "$source_selector" ] && [ "$MOCK_SOURCE_SELECTOR" != "$source_selector" ]; then
      echo "Warning: source selector mismatch (export=$MOCK_SOURCE_SELECTOR expected=$source_selector)"
    fi

    unset RPC_URL
    unset PRIVATE_KEY
    unset CCIP_ROUTER
    set_chain "$dest_chain"
    if [ -z "${CCIP_ROUTER:-}" ]; then
      echo "Missing destination CCIP router for $dest_chain (set chain router env first)."
      exit 1
    fi
    export MOCK_CCIP_ROUTER="$CCIP_ROUTER"

    echo "Relaying message on destination chain $dest_chain..."
    run_forge_script "script/reprieve/RelayExternalMockMessage.s.sol:RelayExternalMockMessage"
    ;;
  cross-chain-rescue-setup-source)
    set_chain "$chain"
    load_lending_addresses_from_config
    load_reprieve_addresses_from_artifact
    export SOURCE_EXECUTOR="${SOURCE_EXECUTOR:-$RESCUE_EXECUTOR}"
    export SOURCE_AAVE_POOL="${SOURCE_AAVE_POOL:-$AAVE_POOL}"
    export SOURCE_AAVE_ADAPTER="${SOURCE_AAVE_ADAPTER:-$AAVE_ADAPTER}"
    run_forge_script "script/reprieve/CrossChainRescueSetupSource.s.sol:CrossChainRescueSetupSource"
    ;;
  cross-chain-rescue-setup-destination)
    set_chain "$chain"
    load_lending_addresses_from_config
    run_forge_script "script/reprieve/CrossChainRescueSetupDestination.s.sol:CrossChainRescueSetupDestination"
    ;;
  cross-chain-rescue-execute)
    set_chain "$chain"
    load_lending_addresses_from_config
    load_reprieve_addresses_from_artifact
    opposite_artifact="$CONTRACTS_DIR/config/reprieve-stack-${OPPOSITE_CHAIN_ID}.json"
    opposite_config="$OPPOSITE_CONFIG_PATH"
    cross_dest_artifact="$CONTRACTS_DIR/config/cross-chain-rescue-destination-${OPPOSITE_CHAIN_ID}.json"
    export RESCUE_MODE="${RESCUE_MODE:-TOP_UP}"
    export SOURCE_CHAIN_SELECTOR="$(selector_for_chain_id "$CHAIN_ID")"
    export DEST_CHAIN_SELECTOR="$(selector_for_chain_id "$OPPOSITE_CHAIN_ID")"
    export DEST_RECEIVER="${DEST_RECEIVER:-$(json_get_string "$opposite_artifact" "CCIPReceiver")}"
    export SOURCE_EXECUTOR="${SOURCE_EXECUTOR:-$RESCUE_EXECUTOR}"
    export SOURCE_AAVE_POOL="${SOURCE_AAVE_POOL:-$AAVE_POOL}"
    export SOURCE_AAVE_ADAPTER="${SOURCE_AAVE_ADAPTER:-$AAVE_ADAPTER}"
    export TARGET_ADAPTER="${TARGET_ADAPTER:-$(json_get_string "$cross_dest_artifact" "targetAdapter")}"
    export TARGET_ADAPTER="${TARGET_ADAPTER:-$(json_get_string "$opposite_config" "CompoundLikeAdapter")}"
    export TARGET_ADAPTER="${TARGET_ADAPTER:-$COMPOUND_ADAPTER}"
    export RESCUE_DEBT_ASSET="${RESCUE_DEBT_ASSET:-$(json_get_string "$cross_dest_artifact" "rescueDebtAsset")}"
    export RESCUE_DEBT_ASSET="${RESCUE_DEBT_ASSET:-$DEBT_ASSET}"
    if [ -z "${DEST_RECEIVER:-}" ] || [ -z "${TARGET_ADAPTER:-}" ]; then
      echo "cross-chain-rescue-execute requires DEST_RECEIVER and TARGET_ADAPTER (env/artifact)."
      exit 1
    fi
    run_forge_script "script/reprieve/CrossChainRescueExecute.s.sol:CrossChainRescueExecute"
    ;;
  same-chain-rescue-setup)
    set_chain "$chain"
    load_lending_addresses_from_config
    load_reprieve_addresses_from_artifact
    export RESCUE_MODE="${RESCUE_MODE:-TOP_UP}"
    run_forge_script "script/reprieve/SameChainRescueSetup.s.sol:SameChainRescueSetup"
    ;;
  reprieve-deploy)
    set_chain "$chain"
    load_lending_addresses_from_config
    echo "Deploying reprieve stack on $CHAIN_NAME..."
    run_forge_script "script/reprieve/DeployReprieveStack.s.sol:DeployReprieveStack"
    ;;
  workflow-receiver-deploy)
    set_chain "$chain"
    load_reprieve_addresses_from_artifact
    resolve_cre_forwarder
    if [ -z "${RESCUE_EXECUTOR:-}" ]; then
      echo "Missing RESCUE_EXECUTOR (deploy reprieve stack first or set env)."
      exit 1
    fi
    if [ -z "${CRE_FORWARDER:-}" ]; then
      echo "Missing CRE_FORWARDER (set CRE_FORWARDER or chain-specific *_CRE_FORWARDER in .env)."
      exit 1
    fi
    echo "Deploying workflow receiver on $CHAIN_NAME..."
    run_forge_script "script/reprieve/DeployWorkflowReceiver.s.sol:DeployWorkflowReceiver"
    ;;
  workflow-receiver-wire)
    set_chain "$chain"
    load_reprieve_addresses_from_artifact
    load_workflow_receiver_from_artifact
    resolve_cre_forwarder
    if [ -z "${WORKFLOW_RECEIVER:-}" ]; then
      echo "Missing WORKFLOW_RECEIVER (run workflow-receiver-deploy first or set env)."
      exit 1
    fi
    if [ -z "${RESCUE_EXECUTOR:-}" ]; then
      echo "Missing RESCUE_EXECUTOR (deploy reprieve stack first or set env)."
      exit 1
    fi
    echo "Wiring workflow receiver on $CHAIN_NAME..."
    run_forge_script "script/reprieve/WireWorkflowReceiver.s.sol:WireWorkflowReceiver"
    ;;
  workflow-receiver-debug-onreport)
    set_chain "$chain"
    calldata_hex="${arg3:-}"
    if [ -z "$calldata_hex" ]; then
      echo "workflow-receiver-debug-onreport requires <chain> <calldata-hex>."
      usage
      exit 1
    fi
    export ONREPORT_CALLDATA="$calldata_hex"
    load_lending_addresses_from_config
    load_reprieve_addresses_from_artifact
    load_workflow_receiver_from_artifact
    setup_artifact="$CONTRACTS_DIR/config/same-chain-rescue-setup-${CHAIN_ID}.json"
    setup_user="$(json_get_path_string "$setup_artifact" '.setup.user')"
    export RESCUE_USER="${RESCUE_USER:-${USER_ADDRESS:-$setup_user}}"
    if [ -z "${WORKFLOW_RECEIVER:-}" ] || [ -z "${RESCUE_EXECUTOR:-}" ]; then
      echo "workflow-receiver-debug-onreport requires WORKFLOW_RECEIVER and RESCUE_EXECUTOR."
      exit 1
    fi
    if [ -z "${RESCUE_USER:-}" ]; then
      echo "Missing RESCUE_USER (set env or run same-chain setup artifact first)."
      exit 1
    fi
    export SOURCE_ADAPTER="${SOURCE_ADAPTER:-$AAVE_ADAPTER}"
    export TARGET_ADAPTER="${TARGET_ADAPTER:-$COMPOUND_ADAPTER}"
    export STEP_COLLATERAL_ASSET="${STEP_COLLATERAL_ASSET:-$COLLATERAL_ASSET}"
    export STEP_DEBT_ASSET="${STEP_DEBT_ASSET:-$DEBT_ASSET}"
    export STEP_COLLATERAL_AMOUNT="${STEP_COLLATERAL_AMOUNT:-${CROSS_TOPUP_COLLATERAL:-1000000000000000000}}"
    export STEP_DEBT_AMOUNT="${STEP_DEBT_AMOUNT:-0}"
    export RESCUE_MODE="${RESCUE_MODE:-TOP_UP}"
    export INCLUDE_METADATA="${INCLUDE_METADATA:-true}"
    export TEMP_SET_FORWARDER="${TEMP_SET_FORWARDER:-true}"
    export RESTORE_FORWARDER="${RESTORE_FORWARDER:-true}"
    export FAIL_ON_REVERT="${FAIL_ON_REVERT:-false}"
    export BROADCAST_DEBUG="${BROADCAST_DEBUG:-false}"
    echo "Debugging workflow receiver onReport on $CHAIN_NAME"
    echo "  Receiver : $WORKFLOW_RECEIVER"
    echo "  Executor : $RESCUE_EXECUTOR"
    echo "  User     : $RESCUE_USER"
    echo "  Mode     : $RESCUE_MODE"
    echo "  Calldata : ${ONREPORT_CALLDATA}"
    echo "  Source   : $SOURCE_ADAPTER"
    echo "  Target   : $TARGET_ADAPTER"
    echo "  Temp fwd : $TEMP_SET_FORWARDER (restore=$RESTORE_FORWARDER)"
    echo "  Broadcast: $BROADCAST_DEBUG"
    if [ "$BROADCAST_DEBUG" = "true" ]; then
      run_forge_script "script/reprieve/DebugWorkflowReceiverOnReport.s.sol:DebugWorkflowReceiverOnReport"
    else
      run_forge_script_readonly "script/reprieve/DebugWorkflowReceiverOnReport.s.sol:DebugWorkflowReceiverOnReport"
    fi
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
