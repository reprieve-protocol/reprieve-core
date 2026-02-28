#!/bin/bash
# Slide 0: Environment validation for Reprieve contracts
# Usage: ./script/reprieve/check-env.sh

set -e

ERRORS=0

echo "=== Reprieve Environment Check ==="
echo ""

# Check required environment variables
check_env() {
    local var_name=$1
    local var_value=$(eval echo \$$var_name)
    
    if [ -z "$var_value" ]; then
        echo "❌ Missing: $var_name"
        ERRORS=$((ERRORS + 1))
    else
        echo "✅ $var_name is set"
    fi
}

echo "Checking RPC endpoints..."
check_env "ARBITRUM_SEPOLIA_RPC"
check_env "BASE_SEPOLIA_RPC"

echo ""
echo "Checking private key..."
check_env "PRIVATE_KEY"

echo ""
echo "Checking CCIP Router addresses..."
check_env "ARBITRUM_SEPOLIA_CCIP_ROUTER"
check_env "BASE_SEPOLIA_CCIP_ROUTER"

echo ""
echo "Checking LINK token addresses..."
check_env "ARBITRUM_SEPOLIA_LINK"
check_env "BASE_SEPOLIA_LINK"

echo ""
echo "Checking deployed contract addresses (for wiring scripts)..."
check_env "COLLATERAL_ASSET"
check_env "DEBT_ASSET"
check_env "AAVE_POOL"
check_env "COMPOUND_MARKET"
check_env "MORPHO_MARKET"

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "✅ All environment variables are set!"
    exit 0
else
    echo "❌ $ERRORS environment variable(s) missing"
    echo ""
    echo "To set missing variables, run:"
    echo "  export VARIABLE_NAME=value"
    exit 1
fi
