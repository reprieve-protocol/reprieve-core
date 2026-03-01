#!/bin/bash
#
# check-env.sh - Environment validation script for Reprieve demo
# Validates required environment variables and RPC endpoints before deployment
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "========================================"
echo "Reprieve Demo Environment Check"
echo "========================================"
echo ""

ERRORS=0
WARNINGS=0

# Check if forge is installed
echo -n "Checking Foundry (forge)... "
if command -v forge &> /dev/null; then
    FORGE_VERSION=$(forge --version)
    echo -e "${GREEN}OK${NC} ($FORGE_VERSION)"
else
    echo -e "${RED}MISSING${NC}"
    echo "  Please install Foundry: https://book.getfoundry.sh/getting-started/installation"
    ((ERRORS++))
fi
echo ""

# Check environment variables
echo "Checking Environment Variables:"
echo "--------------------------------"

# Ethereum Sepolia
if [ -z "$ETHEREUM_SEPOLIA_RPC" ]; then
    echo -e "  ETHEREUM_SEPOLIA_RPC: ${RED}NOT SET${NC}"
    ((ERRORS++))
else
    echo -e "  ETHEREUM_SEPOLIA_RPC: ${GREEN}SET${NC}"
fi

if [ -z "$ETHEREUM_SEPOLIA_DEPLOYER_KEY" ]; then
    echo -e "  ETHEREUM_SEPOLIA_DEPLOYER_KEY: ${YELLOW}NOT SET${NC} (will use default anvil key)"
    ((WARNINGS++))
else
    echo -e "  ETHEREUM_SEPOLIA_DEPLOYER_KEY: ${GREEN}SET${NC}"
fi

# Base Sepolia
if [ -z "$BASE_SEPOLIA_RPC" ]; then
    echo -e "  BASE_SEPOLIA_RPC: ${RED}NOT SET${NC}"
    ((ERRORS++))
else
    echo -e "  BASE_SEPOLIA_RPC: ${GREEN}SET${NC}"
fi

if [ -z "$BASE_SEPOLIA_DEPLOYER_KEY" ]; then
    echo -e "  BASE_SEPOLIA_DEPLOYER_KEY: ${YELLOW}NOT SET${NC} (will use default anvil key)"
    ((WARNINGS++))
else
    echo -e "  BASE_SEPOLIA_DEPLOYER_KEY: ${GREEN}SET${NC}"
fi

echo ""

# Test RPC connections if variables are set
echo "Testing RPC Connections:"
echo "-----------------------"

if [ -n "$ETHEREUM_SEPOLIA_RPC" ]; then
    echo -n "  Ethereum Sepolia RPC... "
    if cast chain-id --rpc-url "$ETHEREUM_SEPOLIA_RPC" &> /dev/null; then
        CHAIN_ID=$(cast chain-id --rpc-url "$ETHEREUM_SEPOLIA_RPC")
        if [ "$CHAIN_ID" == "11155111" ]; then
            echo -e "${GREEN}OK${NC} (chainId: $CHAIN_ID)"
        else
            echo -e "${YELLOW}WRONG CHAIN${NC} (expected: 11155111, got: $CHAIN_ID)"
            ((WARNINGS++))
        fi
    else
        echo -e "${RED}UNREACHABLE${NC}"
        ((ERRORS++))
    fi
fi

if [ -n "$BASE_SEPOLIA_RPC" ]; then
    echo -n "  Base Sepolia RPC... "
    if cast chain-id --rpc-url "$BASE_SEPOLIA_RPC" &> /dev/null; then
        CHAIN_ID=$(cast chain-id --rpc-url "$BASE_SEPOLIA_RPC")
        if [ "$CHAIN_ID" == "84532" ]; then
            echo -e "${GREEN}OK${NC} (chainId: $CHAIN_ID)"
        else
            echo -e "${YELLOW}WRONG CHAIN${NC} (expected: 84532, got: $CHAIN_ID)"
            ((WARNINGS++))
        fi
    else
        echo -e "${RED}UNREACHABLE${NC}"
        ((ERRORS++))
    fi
fi

echo ""

# Check config files
echo "Checking Config Files:"
echo "---------------------"

CONFIG_FILES=(
    "config/ethereum-sepolia.json"
    "config/base-sepolia.json"
)

for file in "${CONFIG_FILES[@]}"; do
    if [ -f "$PROJECT_ROOT/$file" ]; then
        echo -e "  $file: ${GREEN}EXISTS${NC}"
    else
        echo -e "  $file: ${RED}MISSING${NC}"
        ((ERRORS++))
    fi
done

echo ""

# Check folder structure
echo "Checking Folder Structure:"
echo "-------------------------"

FOLDERS=(
    "src/mocks"
    "src/adapters"
    "src/interfaces"
    "src/libs"
    "script/demo"
    "test/demo"
    "config"
)

for folder in "${FOLDERS[@]}"; do
    if [ -d "$PROJECT_ROOT/$folder" ]; then
        echo -e "  $folder/: ${GREEN}EXISTS${NC}"
    else
        echo -e "  $folder/: ${RED}MISSING${NC}"
        ((ERRORS++))
    fi
done

echo ""

# Check interface files
echo "Checking Interface Files:"
echo "------------------------"

INTERFACE_FILES=(
    "src/interfaces/ILendingLikeProtocol.sol"
    "src/interfaces/IDemoOracle.sol"
    "src/interfaces/IReprieveAdapter.sol"
)

for file in "${INTERFACE_FILES[@]}"; do
    if [ -f "$PROJECT_ROOT/$file" ]; then
        echo -e "  $file: ${GREEN}EXISTS${NC}"
    else
        echo -e "  $file: ${RED}MISSING${NC}"
        ((ERRORS++))
    fi
done

echo ""

# Try to compile
echo "Testing Compilation:"
echo "-------------------"
cd "$PROJECT_ROOT"
echo -n "  Running forge build... "
if forge build --silent 2>/dev/null; then
    echo -e "${GREEN}SUCCESS${NC}"
else
    echo -e "${RED}FAILED${NC}"
    ((ERRORS++))
fi

echo ""

# Summary
echo "========================================"
echo "Summary"
echo "========================================"
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}All checks passed!${NC}"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}All required checks passed with $WARNINGS warning(s).${NC}"
    exit 0
else
    echo -e "${RED}Found $ERRORS error(s) and $WARNINGS warning(s).${NC}"
    echo "Please fix errors before proceeding."
    exit 1
fi
