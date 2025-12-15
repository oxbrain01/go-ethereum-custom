#!/bin/bash
# Script để reinitialize cả 2 nodes với cùng genesis file

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

NODE1_DATADIR="${HOME}/local-testnet-node1"
NODE2_DATADIR="${HOME}/local-testnet-node2"
GENESIS_FILE="scripts/genesis-2-validators.json"

echo "⚠️  WARNING: This will DELETE all blockchain data for both nodes!"
echo "   Press Ctrl+C to cancel, or wait 5 seconds to continue..."
sleep 5

echo ""
echo "🛑 Stopping all nodes..."
./scripts/stop-nodes.sh
sleep 2

echo ""
echo "🗑️  Removing old blockchain data..."
rm -rf "${NODE1_DATADIR}/geth"
rm -rf "${NODE2_DATADIR}/geth"

echo "✅ Removed old data"
echo ""

if [ ! -f "$GENESIS_FILE" ]; then
    echo "❌ Genesis file not found: $GENESIS_FILE"
    echo "   Please run ./scripts/setup-2-validators.sh first"
    exit 1
fi

echo "🔨 Reinitializing both nodes with same genesis..."
./build/bin/geth --datadir "$NODE1_DATADIR" init "$GENESIS_FILE"
./build/bin/geth --datadir "$NODE2_DATADIR" init "$GENESIS_FILE"

echo ""
echo "✅ Both nodes reinitialized with same genesis!"
echo ""
echo "💡 Now start both nodes:"
echo "   Terminal 1: ./scripts/start-node1.sh"
echo "   Terminal 2: ./scripts/start-node2.sh"
echo "   Terminal 3: ./scripts/auto-connect.sh"

