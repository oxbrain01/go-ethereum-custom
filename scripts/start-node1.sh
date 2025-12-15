#!/bin/bash
# Script chạy geth node 1 cho private network
# Run this in Terminal 1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

DATADIR="${HOME}/local-testnet-node1"
HTTP_PORT=8546
WS_PORT=8547
P2P_PORT=30303
AUTH_PORT=8551
NETWORKID=1337

echo "🚀 Starting Geth Node 1..."
echo "📁 Data directory: $DATADIR"
echo "🌐 HTTP RPC: http://localhost:$HTTP_PORT"
echo "🔌 WebSocket RPC: ws://localhost:$WS_PORT"
echo "🔗 P2P Port: $P2P_PORT"
echo "🔐 Auth RPC Port: $AUTH_PORT"
echo "🆔 Network ID: $NETWORKID"
echo ""

# Kiểm tra xem geth đã được build chưa
if [ ! -f "./build/bin/geth" ]; then
    echo "❌ Geth not found. Building..."
    make geth
fi

# Kiểm tra data directory
if [ ! -d "$DATADIR" ]; then
    echo "⚠️  Data directory not found: $DATADIR"
    echo "❌ Please run ./scripts/setup-2-validators.sh first"
    exit 1
fi

# Remove old static-nodes.json if exists (deprecated)
if [ -f "${DATADIR}/static-nodes.json" ]; then
    rm -f "${DATADIR}/static-nodes.json"
    echo "🗑️  Removed deprecated static-nodes.json"
fi

# Kiểm tra genesis file
GENESIS_FILE="scripts/genesis-2-validators.json"
if [ ! -f "$GENESIS_FILE" ]; then
    echo "⚠️  Genesis file not found: $GENESIS_FILE"
    echo "❌ Please run ./scripts/setup-2-validators.sh first"
    exit 1
fi

# Lấy validator address và password
VALIDATOR_ADDRESS_FILE="${DATADIR}/validator_address.txt"
PASSWORD_FILE="${DATADIR}/password.txt"

if [ ! -f "$VALIDATOR_ADDRESS_FILE" ]; then
    echo "⚠️  Validator address not found: $VALIDATOR_ADDRESS_FILE"
    echo "❌ Please run ./scripts/setup-2-validators.sh first"
    exit 1
fi

VALIDATOR_ADDRESS=$(cat "$VALIDATOR_ADDRESS_FILE" | tr -d '\n')
PASSWORD=$(cat "$PASSWORD_FILE" 2>/dev/null || echo "validator123")

echo "🔐 Validator Address: $VALIDATOR_ADDRESS"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💡 IMPORTANT: After Node 1 starts, run this in another terminal to save enode:"
echo "   ./scripts/get-node1-enode.sh"
echo ""
echo "   Or in the Node 1 console, run: admin.nodeInfo.enode"
echo "   Then copy the enode and save it to: ${DATADIR}/enode.txt"
echo ""
echo "💡 IMPORTANT: After both nodes start:"
echo "   1. Create config.toml: ./scripts/create-config-toml.sh"
echo "   2. Restart nodes to load config"
echo "   3. Check peers: ./scripts/check-peers.sh"
echo ""
echo "   For Clique consensus, blocks will be created automatically"
echo "   when validators are connected and accounts are unlocked."
echo ""
echo "⚠️  To exit Node 1:"
echo "   - Press Ctrl+C (not Ctrl+D) to stop the node"
echo "   - Or run in another terminal: ./scripts/stop-nodes.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Trap signals để shutdown gracefully
trap 'echo ""; echo "🛑 Shutting down Node 1..."; exit 0' INT TERM

# Build geth command with optimized settings for testnet
GETH_ARGS=(
  --datadir "$DATADIR"
  --networkid "$NETWORKID"
  --port "$P2P_PORT"
  --http --http.addr "0.0.0.0" --http.port "$HTTP_PORT"
  --http.api "eth,net,web3,miner,admin"
  --ws --ws.addr "0.0.0.0" --ws.port "$WS_PORT"
  --ws.api "eth,net,web3,miner,admin"
  --authrpc.addr "0.0.0.0" --authrpc.port "$AUTH_PORT"
  --maxpeers 1
  --nodiscover
  --cache 128
  --cache.database 25
  --cache.trie 10
  --cache.gc 10
  --cache.snapshot 5
  --txpool.globalslots 50
  --txpool.globalqueue 50
)

# Add --config flag if config.toml exists
CONFIG_FILE="${DATADIR}/config.toml"
if [ -f "$CONFIG_FILE" ]; then
    GETH_ARGS+=(--config "$CONFIG_FILE")
    echo "📄 Loading config from: $CONFIG_FILE"
fi

# Chạy geth
./build/bin/geth "${GETH_ARGS[@]}" console

