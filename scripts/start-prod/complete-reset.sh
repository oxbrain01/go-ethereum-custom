#!/bin/bash
# Complete reset script - removes all data and re-initializes from scratch

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

DATADIR="${SCRIPT_DIR}/data"
GETH_BINARY="./build/bin/geth"
GENESIS_FILE="${SCRIPT_DIR}/genesis.json"
RPC_URL="http://localhost:8547"

echo "🔄 Complete Blockchain Reset"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⚠️  WARNING: This will DELETE all blockchain data!"
echo "   All blocks, transactions, and state will be lost."
echo ""
# Auto-confirm if running non-interactively
if [ -t 0 ]; then
    read -p "Are you sure you want to continue? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "❌ Cancelled"
        exit 0
    fi
else
    echo "⚠️  Non-interactive mode - proceeding with reset..."
fi

# Check if node is running
if curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    "$RPC_URL" > /dev/null 2>&1; then
    echo ""
    echo "⚠️  Node is currently running!"
    echo "   Please stop the node first (Ctrl+C in the terminal running start-prod.sh)"
    echo "   Also stop auto-mine.sh if running"
    echo ""
    exit 1
fi

# Check prerequisites
if [ ! -f "$GENESIS_FILE" ]; then
    echo "❌ Error: Genesis file not found: $GENESIS_FILE"
    exit 1
fi

if [ ! -f "$GETH_BINARY" ]; then
    echo "❌ Error: Geth binary not found: $GETH_BINARY"
    echo "   Run: make geth"
    exit 1
fi

# Remove all blockchain data
echo ""
echo "🗑️  Removing existing blockchain data..."
if [ -d "$DATADIR/geth" ]; then
    rm -rf "$DATADIR/geth"
    echo "✅ Removed $DATADIR/geth"
fi

if [ -d "$DATADIR/blobpool" ]; then
    rm -rf "$DATADIR/blobpool"
    echo "✅ Removed $DATADIR/blobpool"
fi

# Create fresh data directory
mkdir -p "$DATADIR"

# Initialize genesis block
echo ""
echo "🔨 Initializing genesis block with HashDB state scheme..."
"$GETH_BINARY" --datadir "$DATADIR" --state.scheme hash init "$GENESIS_FILE"

if [ $? -ne 0 ]; then
    echo "❌ Failed to initialize genesis block"
    exit 1
fi

echo "✅ Genesis block initialized successfully!"
echo ""

# Verify initialization
echo "🔍 Verifying initialization..."
if [ -f "$DATADIR/geth/chaindata/CURRENT" ] || [ -d "$DATADIR/geth/chaindata/ancient" ]; then
    echo "✅ Genesis block database files created"
    
    # Try to verify state is accessible (requires node to be started)
    echo ""
    echo "✅ Reset complete!"
    echo ""
    echo "💡 Next steps:"
    echo "   1. Start the node: ./scripts/start-prod/start-prod.sh"
    echo "   2. In another terminal, start auto-mining: ./scripts/start-prod/auto-mine.sh"
    echo "   3. Wait a few seconds for block 1 to be created"
    echo "   4. Test transaction: ./scripts/start-prod/test-transaction.sh 0.01"
    echo ""
    echo "📝 Note: Using HashDB state scheme for reliable genesis state access"
    echo ""
else
    echo "❌ Genesis block files not found - initialization may have failed"
    exit 1
fi
