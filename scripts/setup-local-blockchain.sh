#!/bin/bash
# Simple script to setup and start a local Ethereum blockchain
# RPC: http://localhost:8546, Network ID: 1337

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

DATADIR="${HOME}/local-blockchain"
HTTP_PORT=8546
WS_PORT=8547
P2P_PORT=30303
NETWORKID=1337
GENESIS_FILE="scripts/simple-genesis.json"

echo "🚀 Setting up Local Ethereum Blockchain"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📁 Data directory: $DATADIR"
echo "🌐 HTTP RPC: http://localhost:$HTTP_PORT"
echo "🔌 WebSocket RPC: ws://localhost:$WS_PORT"
echo "🆔 Network ID: $NETWORKID"
echo ""

# Check if geth is built
if [ ! -f "./build/bin/geth" ]; then
    echo "📦 Building geth..."
    make geth
    if [ $? -ne 0 ]; then
        echo "❌ Failed to build geth"
        exit 1
    fi
    echo "✅ Geth built successfully"
fi

# Check if genesis file exists
if [ ! -f "$GENESIS_FILE" ]; then
    echo "❌ Genesis file not found: $GENESIS_FILE"
    exit 1
fi

# Initialize blockchain if not already initialized
if [ ! -d "$DATADIR/geth" ]; then
    echo "📝 Initializing blockchain..."
    ./build/bin/geth --datadir "$DATADIR" init "$GENESIS_FILE"
    if [ $? -ne 0 ]; then
        echo "❌ Failed to initialize blockchain"
        exit 1
    fi
    echo "✅ Blockchain initialized"
else
    echo "ℹ️  Blockchain already initialized, skipping init step"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Setup complete!"
echo ""
echo "💡 To start the node, run:"
echo "   ./scripts/start-local-blockchain.sh"
echo ""
echo "💡 Or start it manually:"
echo "   ./build/bin/geth --datadir $DATADIR --networkid $NETWORKID \\"
echo "     --http --http.addr 0.0.0.0 --http.port $HTTP_PORT \\"
echo "     --http.api eth,net,web3,personal,miner,admin \\"
echo "     --ws --ws.addr 0.0.0.0 --ws.port $WS_PORT \\"
echo "     --ws.api eth,net,web3,personal,miner,admin \\"
echo "     --allow-insecure-unlock --nodiscover --maxpeers 0"
echo ""

