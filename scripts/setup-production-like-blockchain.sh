#!/bin/bash
# Setup a local Ethereum blockchain that closely mimics production
# Uses Proof of Stake (PoS) with SimulatedBeacon, persistent storage, and production-like settings

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

DATADIR="${HOME}/production-like-blockchain"
HTTP_PORT=8546
WS_PORT=8547
P2P_PORT=30303
AUTH_PORT=8551
NETWORKID=1337
GENESIS_FILE="scripts/production-like-genesis.json"

echo "🚀 Setting up Production-Like Local Ethereum Blockchain"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📁 Data directory: $DATADIR"
echo "🌐 HTTP RPC: http://localhost:$HTTP_PORT"
echo "🔌 WebSocket RPC: ws://localhost:$WS_PORT"
echo "🔐 Auth RPC: http://localhost:$AUTH_PORT"
echo "🆔 Network ID: $NETWORKID"
echo "💡 Consensus: Proof of Stake (PoS) with SimulatedBeacon"
echo "💡 Block time: ~12 seconds (production-like)"
echo "💡 Storage: Persistent (saved to disk)"
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
    echo "📝 Initializing blockchain with production-like genesis..."
    ./build/bin/geth --datadir "$DATADIR" init "$GENESIS_FILE"
    if [ $? -ne 0 ]; then
        echo "❌ Failed to initialize blockchain"
        exit 1
    fi
    echo "✅ Blockchain initialized"
else
    echo "ℹ️  Blockchain already initialized, skipping init step"
    echo "💡 To reinitialize, delete: $DATADIR"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Setup complete!"
echo ""
echo "💡 To start the blockchain, run:"
echo "   ./scripts/start-production-like-blockchain.sh"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

