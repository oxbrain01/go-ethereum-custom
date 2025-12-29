#!/bin/bash
# Start geth in development mode with trace logging enabled
# This script starts a local development node with comprehensive logging

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.." || exit 1

# Configuration
HTTP_PORT=8545
WS_PORT=8546
P2P_PORT=30303
AUTH_PORT=8551
NETWORKID=1337
DATADIR="${SCRIPT_DIR}/data"
LOGDIR="${SCRIPT_DIR}/logs"

# Create directories if they don't exist
mkdir -p "$DATADIR"
mkdir -p "$LOGDIR"

# Check for reset flag
if [ "$1" == "--reset" ] || [ "$1" == "-r" ]; then
    echo "🔄 Resetting data directory..."
    rm -rf "$DATADIR/geth"
    echo "✅ Data directory reset complete"
    echo ""
fi

# Log file with timestamp
LOG_FILE="${LOGDIR}/geth-$(date +%Y%m%d-%H%M%S).log"

echo "🚀 Starting Geth Development Node with Trace Logging"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📁 Data directory: $DATADIR"
echo "📝 Log file: $LOG_FILE"
echo "🌐 HTTP RPC: http://localhost:$HTTP_PORT"
echo "🔌 WebSocket RPC: ws://localhost:$WS_PORT"
echo "🔗 P2P Port: $P2P_PORT"
echo "🔐 Auth RPC Port: $AUTH_PORT"
echo "🆔 Network ID: $NETWORKID"
echo ""

# Check if geth is built
if [ ! -f "./build/bin/geth" ]; then
    echo "❌ Geth not found. Building..."
    make geth
fi

# Note: --dev mode creates an ephemeral network, no genesis initialization needed
# If you want to use a custom genesis, remove --dev flag and initialize manually

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Trace Logging Configuration:"
echo "   • Verbosity: 5 (detail level - maximum)"
echo "   • Log format: terminal (colored output)"
echo "   • VM Debug: enabled"
echo "   • Module verbosity: eth/*=5,core/*=5,consensus/*=5"
echo "   • Logs also written to: $LOG_FILE"
echo ""
echo "💡 Development Mode Features:"
echo "   • Automatic block creation"
echo "   • Pre-funded dev account"
echo "   • Full API access"
echo ""
echo "💡 To stop, press Ctrl+C"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Trap signals for graceful shutdown
trap 'echo ""; echo "🛑 Shutting down..."; exit 0' INT TERM

# Start geth with trace logging
# Using tee to both display and log to file
./build/bin/geth \
  --dev \
  --dev.period 5 \
  --datadir "$DATADIR" \
  --networkid "$NETWORKID" \
  --port "$P2P_PORT" \
  --http \
  --http.addr "0.0.0.0" \
  --http.port "$HTTP_PORT" \
  --http.api "eth,net,web3,personal,miner,admin,txpool,engine,debug,trace" \
  --ws \
  --ws.addr "0.0.0.0" \
  --ws.port "$WS_PORT" \
  --ws.api "eth,net,web3,personal,miner,admin,debug,trace" \
  --authrpc.addr "0.0.0.0" \
  --authrpc.port "$AUTH_PORT" \
  --allow-insecure-unlock \
  --nodiscover \
  --maxpeers 0 \
  --verbosity 5 \
  --log.vmodule "eth/*=5,core/*=5,consensus/*=5,state/*=5,vm/*=5,txpool/*=5,miner/*=5" \
  --log.format terminal \
  --vmdebug \
  --cache 512 \
  --cache.database 50 \
  --cache.trie 50 \
  --cache.gc 25 \
  2>&1 | tee "$LOG_FILE"

