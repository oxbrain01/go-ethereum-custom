#!/bin/bash
# Script to check if genesis block was properly initialized

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

DATADIR="${SCRIPT_DIR}/data"
GETH_BINARY="./build/bin/geth"
GENESIS_FILE="${SCRIPT_DIR}/genesis.json"

echo "🔍 Checking Genesis Block Initialization"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if database exists
if [ ! -d "$DATADIR/geth/chaindata" ]; then
    echo "❌ Error: Database not found at $DATADIR/geth/chaindata"
    echo "   Run start-prod.sh first to initialize the blockchain"
    exit 1
fi

# Check genesis file
if [ ! -f "$GENESIS_FILE" ]; then
    echo "❌ Error: Genesis file not found: $GENESIS_FILE"
    exit 1
fi

echo "📊 Checking blockchain state..."
echo ""

# Get chain ID from database
CHAIN_ID=$(./build/bin/geth --datadir "$DATADIR" attach --exec "eth.chainId" 2>/dev/null | tr -d '\n' || echo "N/A")
EXPECTED_CHAIN_ID=$(grep -o '"chainId"[[:space:]]*:[[:space:]]*[0-9]*' "$GENESIS_FILE" | grep -o '[0-9]*' | head -1)

echo "   Chain ID in database: $CHAIN_ID"
echo "   Chain ID in genesis:   $EXPECTED_CHAIN_ID"

if [ "$CHAIN_ID" != "$EXPECTED_CHAIN_ID" ]; then
    echo "   ⚠️  Chain ID mismatch! Database may need to be re-initialized."
fi

# Get block number
BLOCK_NUM=$(./build/bin/geth --datadir "$DATADIR" attach --exec "eth.blockNumber" 2>/dev/null | tr -d '\n' || echo "N/A")
echo "   Current block: $BLOCK_NUM"
echo ""

# Check balances of pre-funded accounts
echo "💰 Checking pre-funded account balances..."
ACCOUNTS=(
    "0x356981ee849c96fC40e78B0B22715345E57746fb"
    "0x3bE69C0DEf08196BEE31D463741Df2B92D3eaf8E"
    "0xC4fa658C3C835b316CaCB52338eD9ebbce2631D7"
    "0x1120CFB327baedC2f2638D75Db0935b7f3CC934b"
    "0x554bdA38d6635155b06Faa43189B52D9eD579f70"
)

for account in "${ACCOUNTS[@]}"; do
    BALANCE=$(./build/bin/geth --datadir "$DATADIR" attach --exec "eth.getBalance('$account')" 2>/dev/null | tr -d '\n' || echo "0")
    BALANCE_ETH=$(python3 -c "print($BALANCE / 1000000000000000000)" 2>/dev/null || echo "0")
    echo "   $account: $BALANCE_ETH ETH"
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if balances are zero
FIRST_BALANCE=$(./build/bin/geth --datadir "$DATADIR" attach --exec "eth.getBalance('${ACCOUNTS[0]}')" 2>/dev/null | tr -d '\n' || echo "0")

if [ "$FIRST_BALANCE" = "0" ] || [ -z "$FIRST_BALANCE" ]; then
    echo "⚠️  Warning: Account balances are zero!"
    echo ""
    echo "   This could mean:"
    echo "   1. Genesis block wasn't properly initialized"
    echo "   2. Database was initialized with a different genesis file"
    echo "   3. Node needs to be restarted"
    echo ""
    echo "   To fix, try:"
    echo "   1. Stop the node (Ctrl+C in start-prod.sh terminal)"
    echo "   2. Run: ./scripts/start-prod/force-reset.sh"
    echo "   3. Restart: ./scripts/start-prod/start-prod.sh"
    exit 1
else
    echo "✅ Genesis block appears to be properly initialized"
fi
