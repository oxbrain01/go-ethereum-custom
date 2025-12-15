#!/bin/bash
# Script chạy geth node 2 cho private network
# Run this in Terminal 2 (after node 1 is running)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

DATADIR="${HOME}/local-testnet-node2"
HTTP_PORT=8548
WS_PORT=8549
P2P_PORT=30304
AUTH_PORT=8552
NETWORKID=1337
NODE1_DATADIR="${HOME}/local-testnet-node1"

echo "🚀 Starting Geth Node 2..."
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

# Try to get node 1's enode address
NODE1_ENODE=""
NODE1_ENODE_FILE="${NODE1_DATADIR}/enode.txt"

# First try to read from saved file
if [ -f "$NODE1_ENODE_FILE" ]; then
    NODE1_ENODE_RAW=$(cat "$NODE1_ENODE_FILE" | tr -d '\n')
    # Clean up enode - remove ?discport=0 if present
    NODE1_ENODE=$(echo "$NODE1_ENODE_RAW" | sed 's/?discport=0//' | sed 's/@127\.0\.0\.1:30303/@127.0.0.1:30303/')
    echo "✅ Found Node 1 enode from file: $NODE1_ENODE"
else
    # Try to get it by attaching to node 1 (retry up to 5 times)
    echo "🔍 Trying to get Node 1's enode address..."
    echo "   (Make sure Node 1 is running first!)"
    
    RETRY_COUNT=0
    MAX_RETRIES=5
    
    while [ -z "$NODE1_ENODE" ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if [ -d "$NODE1_DATADIR" ]; then
            NODE1_ENODE_RAW=$(./build/bin/geth attach --exec "admin.nodeInfo.enode" --datadir "$NODE1_DATADIR" 2>/dev/null | tr -d '"' | tr -d '\n' | grep -oE 'enode://[^?]+' || echo "")
            
            if [ -n "$NODE1_ENODE_RAW" ]; then
                # Remove ?discport=0 if present and add proper port
                NODE1_ENODE=$(echo "$NODE1_ENODE_RAW" | sed 's/?discport=0//' | sed 's/@127\.0\.0\.1:30303/@127.0.0.1:30303/')
                echo "$NODE1_ENODE" > "$NODE1_ENODE_FILE"
                echo "✅ Got Node 1 enode: $NODE1_ENODE"
                break
            else
                RETRY_COUNT=$((RETRY_COUNT + 1))
                if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                    echo "   Retry $RETRY_COUNT/$MAX_RETRIES: Waiting for Node 1 to be ready..."
                    sleep 2
                fi
            fi
        else
            echo "   Node 1 data directory not found. Waiting..."
            sleep 2
            RETRY_COUNT=$((RETRY_COUNT + 1))
        fi
    done
fi

# Get validator address and password for Node 2
VALIDATOR_ADDRESS_FILE="${DATADIR}/validator_address.txt"
PASSWORD_FILE="${DATADIR}/password.txt"

if [ ! -f "$VALIDATOR_ADDRESS_FILE" ]; then
    echo "⚠️  Validator address not found: $VALIDATOR_ADDRESS_FILE"
    echo "❌ Please run ./scripts/setup-2-validators.sh first"
    exit 1
fi

VALIDATOR_ADDRESS=$(cat "$VALIDATOR_ADDRESS_FILE" | tr -d '\n')
PASSWORD=$(cat "$PASSWORD_FILE" 2>/dev/null || echo "validator123")

# Build geth command arguments with optimized settings for testnet
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

# Remove old static-nodes.json if exists (deprecated)
if [ -f "${DATADIR}/static-nodes.json" ]; then
    rm -f "${DATADIR}/static-nodes.json"
    echo "🗑️  Removed deprecated static-nodes.json"
fi

# Create config.toml if node 1 enode exists
if [ -n "$NODE1_ENODE" ]; then
    echo "🔗 Setting up static connection to Node 1..."
    echo "   Enode: $NODE1_ENODE"
    
    # Clean enode for bootnodes (remove ?discport=0)
    NODE1_ENODE_CLEAN=$(echo "$NODE1_ENODE" | sed 's/?discport=0//')
    
    # Create config.toml file with static nodes
    CONFIG_FILE="${DATADIR}/config.toml"
    cat > "$CONFIG_FILE" <<EOF
[Node.P2P]
StaticNodes = ["$NODE1_ENODE_CLEAN"]
EOF
    echo "   ✅ Created config.toml with static node"
    
    # Also add as bootnodes for initial connection (use clean version)
    GETH_ARGS+=(--bootnodes "$NODE1_ENODE_CLEAN")
else
    echo "⚠️  Node 1 enode not found after 5 attempts."
    echo "   Node 2 will start but may not connect to Node 1 automatically."
    echo ""
    echo "   To connect manually:"
    echo "   1. In Node 1 console, run: admin.nodeInfo.enode"
    echo "   2. Copy the enode address"
    echo "   3. In Node 2 console, run: admin.addPeer(\"enode://...\")"
    echo ""
    echo "   Or run this script in another terminal:"
    echo "   ./scripts/get-node1-enode.sh"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Starting Node 2..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "💡 IMPORTANT: After both nodes start:"
echo "   1. Create config.toml: ./scripts/create-config-toml.sh"
echo "   2. Restart nodes to load config"
echo "   3. Check peers: ./scripts/check-peers.sh"
echo ""
echo "   For Clique consensus, blocks will be created automatically"
echo "   when validators are connected and accounts are unlocked."
echo ""
echo "⚠️  To exit Node 2:"
echo "   - Press Ctrl+C (not Ctrl+D) to stop the node"
echo "   - Or run in another terminal: ./scripts/stop-nodes.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Trap signals để shutdown gracefully
trap 'echo ""; echo "🛑 Shutting down Node 2..."; exit 0' INT TERM

# Chạy geth
./build/bin/geth "${GETH_ARGS[@]}" console

