#!/bin/bash
# Script to start Geth with production-like configuration
# Uses config.toml file for configuration (production-style)

set -e

# Parse command line arguments
QUIET=false
VERBOSITY=3
SHOW_LOGS=true
LOG_TO_FILE=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --quiet|-q)
            QUIET=true
            VERBOSITY=2
            shift
            ;;
        --verbosity|-v)
            VERBOSITY="$2"
            shift 2
            ;;
        --no-logs|--silent)
            SHOW_LOGS=false
            shift
            ;;
        --log-file)
            LOG_TO_FILE=true
            SHOW_LOGS=false
            shift
            ;;
        --help|-h)
            echo "Usage: $(basename "$0") [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --quiet, -q          Suppress INFO logs (sets verbosity to 2)"
            echo "  --verbosity, -v NUM  Set log verbosity (0-5, default: 3)"
            echo "  --no-logs, --silent  Don't show logs in terminal (logs still saved to file)"
            echo "  --log-file           Only log to file, don't show in terminal"
            echo "  --help, -h           Show this help message"
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1 (use --help)"
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

# Verify project root
if [ ! -f "Makefile" ] || [ ! -f "go.mod" ]; then
    echo "❌ Error: Could not find project root"
    exit 1
fi

# Configuration
PROD_DIR="$SCRIPT_DIR"
DATADIR="${PROD_DIR}/data"
CONFIG_FILE="${PROD_DIR}/config.toml"
GENESIS_FILE="${PROD_DIR}/genesis.json"
PASSWORD_FILE="${PROD_DIR}/.password"
VALIDATOR_ADDRESS="0x356981ee849c96fC40e78B0B22715345E57746fb"
SCRIPT_LOCK_FILE="${PROD_DIR}/.start-prod.lock"
GETH_BINARY="./build/bin/geth"
HTTP_PORT=8547
WS_PORT=8548
AUTH_PORT=8552
P2P_PORT=30303
NETWORK_ID=2026

echo "🚀 Starting Geth with Production Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Lock file check
if [ -f "$SCRIPT_LOCK_FILE" ]; then
    LOCK_PID=$(cat "$SCRIPT_LOCK_FILE" 2>/dev/null)
    if [ ! -z "$LOCK_PID" ] && ps -p "$LOCK_PID" > /dev/null 2>&1; then
        echo "⚠️  Script already running (PID: $LOCK_PID)"
        echo "   To stop it, run: kill $LOCK_PID"
        exit 1
    else
        # Stale lock file - remove it
        echo "🧹 Removing stale lock file (PID $LOCK_PID no longer running)"
        rm -f "$SCRIPT_LOCK_FILE"
    fi
fi
echo $$ > "$SCRIPT_LOCK_FILE"

# Helper function to kill processes
kill_processes() {
    local pattern="$1"
    local name="$2"
    local pids=$(ps aux | grep -E "$pattern" | awk '{print $2}' | tr '\n' ' ')
    if [ ! -z "$pids" ]; then
        echo "🛑 Stopping existing $name processes..."
        for pid in $pids; do
            kill -TERM "$pid" 2>/dev/null || true
        done
        sleep 2
        for pid in $pids; do
            ps -p "$pid" > /dev/null 2>&1 && kill -9 "$pid" 2>/dev/null || true
        done
    fi
}

# Stop existing processes
kill_processes "[g]eth.*--config.*config.toml|[g]eth.*--datadir.*start-prod" "geth"
kill_processes "[p]ython.*beacon-simulator-fixed.py" "beacon simulator"

# Check and kill processes on ports
if command -v lsof > /dev/null 2>&1; then
    for port in $HTTP_PORT $WS_PORT $AUTH_PORT; do
        lsof -ti:$port 2>/dev/null | xargs kill -TERM 2>/dev/null || true
    done
    sleep 1
    for port in $HTTP_PORT $WS_PORT $AUTH_PORT; do
        lsof -ti:$port 2>/dev/null | xargs kill -9 2>/dev/null || true
    done
fi

# Remove stale lock files
rm -f "${DATADIR}/geth/LOCK" 2>/dev/null || true

# Build geth if needed
if [ ! -f "$GETH_BINARY" ]; then
    echo "📦 Building geth..."
    make geth || exit 1
fi

# Setup directories and files
mkdir -p "$DATADIR"
mkdir -p "${DATADIR}/blobpool"
if [ ! -f "$PASSWORD_FILE" ]; then
    echo "validator123" > "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"
fi

# Setup validator account
KEYSTORE_DIR="${DATADIR}/keystore"
VALIDATOR_PRIVATE_KEY="0x9de1394869030ea18ee8930c533722d71f6990b5576dee849b9c23b7d094c186"
ACCOUNT_EXISTS=false

if [ -d "$KEYSTORE_DIR" ]; then
    VALIDATOR_ADDRESS_LOWER=$(echo "$VALIDATOR_ADDRESS" | tr '[:upper:]' '[:lower:]')
    for keystore_file in "$KEYSTORE_DIR"/*; do
        [ -f "$keystore_file" ] || continue
        FILE_ADDRESS=$(basename "$keystore_file" | grep -oE '[a-fA-F0-9]{40}' | head -1)
        [ -z "$FILE_ADDRESS" ] && continue
        if [ "0x$(echo "$FILE_ADDRESS" | tr '[:upper:]' '[:lower:]')" = "$VALIDATOR_ADDRESS_LOWER" ]; then
            ACCOUNT_EXISTS=true
            break
        fi
    done
fi

if [ "$ACCOUNT_EXISTS" = false ]; then
    echo "🔑 Importing validator account..."
    # Create temporary key file for import
    # Remove 0x prefix and any whitespace/newlines
    TMP_KEYFILE=$(mktemp)
    echo "$VALIDATOR_PRIVATE_KEY" | sed 's/^0x//' | tr -d '\n\r ' > "$TMP_KEYFILE"
    # geth account import requires the keyfile as the only argument
    # Password flag must come before the keyfile argument
    "$GETH_BINARY" --datadir "$DATADIR" account import --password "$PASSWORD_FILE" "$TMP_KEYFILE" 2>&1 | grep -v "Maximum peer count\|Brain-log" || {
        echo "⚠️  Failed to import account, creating new one..."
        "$GETH_BINARY" --datadir "$DATADIR" account new --password "$PASSWORD_FILE" > /dev/null 2>&1
    }
    rm -f "$TMP_KEYFILE"
fi

# Initialize genesis
if [ ! -d "$DATADIR/geth/chaindata" ]; then
    [ ! -f "$GENESIS_FILE" ] && { echo "❌ Genesis file not found: $GENESIS_FILE"; exit 1; }
    echo "🔨 Initializing blockchain from genesis..."
    "$GETH_BINARY" --datadir "$DATADIR" init "$GENESIS_FILE" || exit 1
fi

# Create config.toml if needed
if [ ! -f "$CONFIG_FILE" ]; then
    echo "📝 Creating production config.toml..."
    "$GETH_BINARY" \
        --datadir "$DATADIR" \
        --networkid "$NETWORK_ID" \
        --port "$P2P_PORT" \
        --http --http.addr "0.0.0.0" --http.port "$HTTP_PORT" \
        --http.api "eth,net,web3,engine,admin,miner,txpool,debug" \
        --http.corsdomain "*" \
        --http.vhosts "*" \
        --ws --ws.addr "0.0.0.0" --ws.port "$WS_PORT" \
        --ws.api "eth,net,web3,engine,admin,miner,txpool" \
        --ws.origins "*" \
        --authrpc.addr "0.0.0.0" --authrpc.port "$AUTH_PORT" --authrpc.vhosts "*" \
        --cache 4096 --cache.database 50 --cache.trie 25 --cache.gc 25 --cache.snapshot 10 \
        --txpool.globalslots 4096 --txpool.globalqueue 1024 \
        --txpool.accountslots 16 --txpool.accountqueue 4 \
        --txpool.lifetime 3h \
        --blobpool.datadir "${DATADIR}/blobpool" \
        --blobpool.datacap 10737418240 \
        --syncmode snap \
        --gcmode archive \
        --txlookuplimit 0 \
        dumpconfig > "$CONFIG_FILE" 2>/dev/null || {
        cat > "$CONFIG_FILE" <<EOF
[Eth]
NetworkId = $NETWORK_ID
SyncMode = "snap"
TxLookupLimit = 0

[Node]
DataDir = "$DATADIR"
HTTPHost = "0.0.0.0"
HTTPPort = $HTTP_PORT
HTTPModules = ["eth", "net", "web3", "engine", "admin", "miner", "txpool", "debug"]
HTTPCors = ["*"]
HTTPVhosts = ["*"]
WSHost = "0.0.0.0"
WSPort = $WS_PORT
WSModules = ["eth", "net", "web3", "engine", "admin", "miner", "txpool"]
WSOrigins = ["*"]
AuthAddr = "0.0.0.0"
AuthPort = $AUTH_PORT
AuthVhosts = ["*"]

[Node.P2P]
MaxPeers = 50
NoDiscovery = false

[Eth.Cache]
Cache = 4096
CacheDatabase = 50
CacheTrie = 25
CacheGCFull = 25
CacheSnapshot = 10

[Eth.TxPool]
Locals = []
NoLocals = false
Journal = "transactions.rlp"
Rejournal = 3600000000000
PriceLimit = 1000000000
PriceBump = 10
AccountSlots = 16
GlobalSlots = 4096
AccountQueue = 4
GlobalQueue = 1024
Lifetime = 10800000000000

[Eth.BlobPool]
DataDir = "${DATADIR}/blobpool"
Datacap = 10737418240
PriceBump = 100
EOF
    }
else
    # Update existing config to include all production APIs if not present
    echo "📝 Updating config.toml with production APIs..."
    UPDATED=false
    
    # Update HTTPModules - add txpool and debug if not present
    if grep -q "HTTPModules" "$CONFIG_FILE"; then
        if ! grep -q '"txpool"' "$CONFIG_FILE" && ! grep -q "'txpool'" "$CONFIG_FILE"; then
            sed -i.bak 's/HTTPModules = \[\(.*\)\]/HTTPModules = [\1, "txpool", "debug"]/' "$CONFIG_FILE" 2>/dev/null || \
            sed -i.bak "s/HTTPModules = \[\([^]]*\)\]/HTTPModules = [\1, 'txpool', 'debug']/" "$CONFIG_FILE" 2>/dev/null || true
            UPDATED=true
        fi
        # Remove personal API if present (unavailable in newer geth)
        if grep -q '"personal"' "$CONFIG_FILE" || grep -q "'personal'" "$CONFIG_FILE"; then
            sed -i.bak 's/, "personal"//g' "$CONFIG_FILE" 2>/dev/null || true
            sed -i.bak "s/, 'personal'//g" "$CONFIG_FILE" 2>/dev/null || true
            sed -i.bak 's/"personal", //g' "$CONFIG_FILE" 2>/dev/null || true
            sed -i.bak "s/'personal', //g" "$CONFIG_FILE" 2>/dev/null || true
            UPDATED=true
        fi
    fi
    
    # Update WSModules - add txpool if not present
    if grep -q "WSModules" "$CONFIG_FILE"; then
        if ! grep -q '"txpool"' "$CONFIG_FILE" && ! grep -q "'txpool'" "$CONFIG_FILE"; then
            sed -i.bak 's/WSModules = \[\(.*\)\]/WSModules = [\1, "txpool"]/' "$CONFIG_FILE" 2>/dev/null || \
            sed -i.bak "s/WSModules = \[\([^]]*\)\]/WSModules = [\1, 'txpool']/" "$CONFIG_FILE" 2>/dev/null || true
            UPDATED=true
        fi
    fi
    
    [ "$UPDATED" = true ] && echo "   ✓ Config updated with production APIs"
    rm -f "${CONFIG_FILE}.bak" 2>/dev/null || true
fi

# Configuration summary
CHAIN_ID=$(grep -o '"chainId"[[:space:]]*:[[:space:]]*[0-9]*' "$GENESIS_FILE" 2>/dev/null | grep -o '[0-9]*' | head -1 || echo "N/A")
echo "📋 Config: $CONFIG_FILE | Data: $DATADIR | ChainId: $CHAIN_ID | Verbosity: $VERBOSITY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Cleanup function
GETH_PID=""
BEACON_PID=""
TEE_PID=""
cleanup() {
    if [ "$SHOW_LOGS" = false ]; then
        echo ""
        echo "🛑 Shutting down..."
    fi
    [ ! -z "$BEACON_PID" ] && kill "$BEACON_PID" 2>/dev/null || true
    [ ! -z "$GETH_PID" ] && kill "$GETH_PID" 2>/dev/null || true
    # Kill tee process if it exists (it will exit when geth exits)
    pkill -P $$ tee 2>/dev/null || true
    rm -f "$SCRIPT_LOCK_FILE"
    exit 0
}
trap cleanup INT TERM EXIT

# Start geth with full production features
echo "🚀 Starting Geth with Production Configuration..."
echo "   • Full mainnet-like features enabled"
echo "   • Custom POL validator node"
echo "   • All APIs enabled (eth, net, web3, engine, admin, miner, txpool, debug)"
echo "   • GraphQL endpoint enabled"
echo "   • Transaction pool optimized"
echo "   • Blob transaction support (EIP-4844)"
echo "   • Archive mode for full state history"

# Build geth command with all production flags
GETH_CMD=(
    "$GETH_BINARY"
    --config "$CONFIG_FILE"
    --override.genesis "$GENESIS_FILE"
    --networkid "$NETWORK_ID"
    --port "$P2P_PORT"
    --verbosity "$VERBOSITY"
    --graphql
    --graphql.corsdomain "*"
    --graphql.vhosts "*"
    --http
    --http.addr "0.0.0.0"
    --http.port "$HTTP_PORT"
    --http.api "eth,net,web3,engine,admin,miner,txpool,debug"
    --http.corsdomain "*"
    --http.vhosts "*"
    --ws
    --ws.addr "0.0.0.0"
    --ws.port "$WS_PORT"
    --ws.api "eth,net,web3,engine,admin,miner,txpool"
    --ws.origins "*"
    --authrpc.addr "0.0.0.0"
    --authrpc.port "$AUTH_PORT"
    --authrpc.vhosts "*"
    --unlock "$VALIDATOR_ADDRESS"
    --password "$PASSWORD_FILE"
    --allow-insecure-unlock
    --miner.etherbase "$VALIDATOR_ADDRESS"
    --syncmode full
    --gcmode archive
    --txlookuplimit 0
    --cache 4096
    --cache.database 50
    --cache.trie 25
    --cache.gc 25
    --cache.snapshot 10
    --txpool.globalslots 4096
    --txpool.globalqueue 1024
    --txpool.accountslots 16
    --txpool.accountqueue 4
    --txpool.lifetime 3h
    --blobpool.datadir "${DATADIR}/blobpool"
    --blobpool.datacap 10737418240
    --maxpeers 50
    --state.scheme hash
)

if [ "$SHOW_LOGS" = true ]; then
    # Show logs in terminal and also save to file using tee
    "${GETH_CMD[@]}" 2>&1 | tee "$SCRIPT_DIR/start-prod.log" &
    GETH_PID=$!
else
    # Only log to file (background, no terminal output)
    "${GETH_CMD[@]}" >> "$SCRIPT_DIR/start-prod.log" 2>&1 &
    GETH_PID=$!
fi

# Give geth a moment to start
sleep 2

# Check if geth process is still running
if ! kill -0 "$GETH_PID" 2>/dev/null; then
    echo "❌ Failed to start Geth!"
    echo "   Check the logs: tail -f $SCRIPT_DIR/start-prod.log"
    exit 1
fi

# Wait for node to be ready
echo "⏳ Waiting for node to be ready..."
sleep 3
for i in {1..30}; do
    BLOCK_NUM=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        http://localhost:$HTTP_PORT 2>/dev/null | grep -oE '"result":"0x[0-9a-f]+"' | cut -d'"' -f4)
    [ ! -z "$BLOCK_NUM" ] && echo "✅ Node ready" && break
    [ $i -eq 30 ] && echo "⚠️  Node may not be fully ready" || sleep 1
done

# Start mining to ensure blocks are created when transactions are pending
echo "⛏️  Starting miner for block creation..."
MINER_START=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"miner_start","params":[1],"id":1}' \
    http://localhost:$HTTP_PORT 2>/dev/null)

MINER_ERROR=$(echo "$MINER_START" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('error', {}).get('message', '') if 'error' in d else '')" 2>/dev/null || echo "")

if [ -z "$MINER_ERROR" ]; then
    echo "✅ Miner started - blocks will be created automatically when transactions are pending"
else
    echo "⚠️  Could not start miner: $MINER_ERROR"
    echo "   Blocks should still be created automatically by Clique validator"
fi

# Display validator and POL information
echo ""
echo "🔐 Validator Configuration:"
echo "   • Validator Address: $VALIDATOR_ADDRESS"
echo "   • Account unlocked and ready for block signing"
echo "   • POL Distributor: 0x9595959595959595959595959595959595959595"
echo ""
echo "📊 Production Features Enabled:"
echo "   • Full state history (archive mode)"
echo "   • Transaction pool: 4096 slots, 1024 queue"
echo "   • Blob pool: 10GB capacity"
echo "   • Cache: 4096MB (optimized for production)"
echo "   • Max peers: 50"
echo "   • All Ethereum forks enabled from genesis"
echo "   • EIP-4844 blob transactions supported"
echo ""
echo "🌐 Network Endpoints:"
echo "   • HTTP RPC: http://localhost:$HTTP_PORT"
echo "   • WebSocket: ws://localhost:$WS_PORT"
echo "   • GraphQL: http://localhost:$HTTP_PORT/graphql"
echo "   • Engine API: http://localhost:$AUTH_PORT"
echo "   • P2P Port: $P2P_PORT"
echo ""
echo "ℹ️  Note: Clique (PoA) consensus - blocks created by authorized signers"
echo "   Your validator will automatically create blocks when authorized"

# Monitor geth process and keep script running
if [ "$SHOW_LOGS" = true ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 Geth logs are displayed below (also saved to start-prod.log)"
    echo "💡 Press Ctrl+C to stop the node"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    # Wait for geth process - logs will be shown via tee
    wait $GETH_PID
else
    echo "✅ Node started successfully!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "💡 Node is running in the background"
    echo "💡 View logs: tail -f $SCRIPT_DIR/start-prod.log"
    echo "💡 Check status: curl -X POST -H \"Content-Type: application/json\" --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' http://localhost:$HTTP_PORT"
    echo "💡 Press Ctrl+C to stop the node"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    # Wait for geth process, but check if it's still running
    while kill -0 "$GETH_PID" 2>/dev/null; do
        sleep 5
    done
fi

# If we get here, geth has exited
echo ""
echo "⚠️  Geth process has exited"
echo "   Checking exit status..."

# Check if geth is still running (might have been restarted or something)
if ! ps -p "$GETH_PID" > /dev/null 2>&1; then
    echo "❌ Geth process is no longer running"
    echo "   Check the logs for errors: tail -f $SCRIPT_DIR/start-prod.log"
    exit 1
fi

wait $GETH_PID
