#!/bin/bash
# Script to start Geth with production-like configuration
# Uses config.toml file for configuration (production-style)

set -e

# Parse command line arguments
QUIET=false
VERBOSITY=3

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
        --help|-h)
            echo "Usage: $(basename "$0") [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --quiet, -q          Suppress INFO logs (sets verbosity to 2)"
            echo "  --verbosity, -v NUM  Set log verbosity (0-5, default: 3)"
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

echo "🚀 Starting Geth with Production Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Lock file check
if [ -f "$SCRIPT_LOCK_FILE" ]; then
    LOCK_PID=$(cat "$SCRIPT_LOCK_FILE" 2>/dev/null)
    if [ ! -z "$LOCK_PID" ] && ps -p "$LOCK_PID" > /dev/null 2>&1; then
        echo "⚠️  Script already running (PID: $LOCK_PID)"
        exit 1
    fi
    rm -f "$SCRIPT_LOCK_FILE"
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
    TMP_KEYFILE=$(mktemp)
    echo "$VALIDATOR_PRIVATE_KEY" | tr -d '\n' > "$TMP_KEYFILE"
    echo "validator123" | "$GETH_BINARY" --datadir "$DATADIR" account import "$TMP_KEYFILE" --password <(echo "validator123") 2>/dev/null || {
        echo "validator123" | "$GETH_BINARY" --datadir "$DATADIR" account new --password <(echo "validator123") > /dev/null 2>&1
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
    echo "📝 Creating config.toml..."
    "$GETH_BINARY" \
        --datadir "$DATADIR" \
        --http --http.addr "0.0.0.0" --http.port "$HTTP_PORT" --http.api "eth,net,web3,engine,admin" \
        --ws --ws.addr "0.0.0.0" --ws.port "$WS_PORT" --ws.api "eth,net,web3,engine,admin" \
        --authrpc.addr "0.0.0.0" --authrpc.port "$AUTH_PORT" --authrpc.vhosts "*" \
        --cache 4096 --cache.database 50 --cache.trie 25 --cache.gc 25 --cache.snapshot 10 \
        dumpconfig > "$CONFIG_FILE" 2>/dev/null || {
        cat > "$CONFIG_FILE" <<EOF
[Eth]
SyncMode = "snap"

[Node]
DataDir = "$DATADIR"
HTTPHost = "0.0.0.0"
HTTPPort = $HTTP_PORT
HTTPModules = ["eth", "net", "web3", "engine", "admin"]
WSHost = "0.0.0.0"
WSPort = $WS_PORT
WSModules = ["eth", "net", "web3", "engine", "admin"]
AuthAddr = "0.0.0.0"
AuthPort = $AUTH_PORT
AuthVhosts = ["*"]

[Eth.Cache]
Cache = 4096
CacheDatabase = 50
CacheTrie = 25
CacheGCFull = 25
CacheSnapshot = 10
EOF
    }
fi

# Configuration summary
CHAIN_ID=$(grep -o '"chainId"[[:space:]]*:[[:space:]]*[0-9]*' "$GENESIS_FILE" 2>/dev/null | grep -o '[0-9]*' | head -1 || echo "N/A")
echo "📋 Config: $CONFIG_FILE | Data: $DATADIR | ChainId: $CHAIN_ID | Verbosity: $VERBOSITY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Cleanup function
GETH_PID=""
BEACON_PID=""
cleanup() {
    echo ""
    echo "🛑 Shutting down..."
    [ ! -z "$BEACON_PID" ] && kill "$BEACON_PID" 2>/dev/null || true
    [ ! -z "$GETH_PID" ] && kill "$GETH_PID" 2>/dev/null || true
    rm -f "$SCRIPT_LOCK_FILE"
    exit 0
}
trap cleanup INT TERM EXIT

# Start geth
echo "🚀 Starting Geth..."
"$GETH_BINARY" \
    --config "$CONFIG_FILE" \
    --verbosity "$VERBOSITY" \
    --graphql \
    --unlock "$VALIDATOR_ADDRESS" \
    --password "$PASSWORD_FILE" \
    --allow-insecure-unlock \
    --miner.etherbase "$VALIDATOR_ADDRESS" &
GETH_PID=$!

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

# Start beacon simulator if available
BEACON_SCRIPT="${PROJECT_ROOT}/scripts/beacon-simulator-fixed.py"
JWT_SECRET_PATH="${DATADIR}/geth/jwtsecret"
if [ -f "$BEACON_SCRIPT" ] && command -v python3 > /dev/null 2>&1; then
    for i in {1..10}; do
        [ -f "$JWT_SECRET_PATH" ] && break
        sleep 1
    done
    if [ -f "$JWT_SECRET_PATH" ]; then
        cd "$PROJECT_ROOT" || exit 1
        python3 "$BEACON_SCRIPT" &
        BEACON_PID=$!
        echo "✅ Beacon simulator started (PID: $BEACON_PID)"
    fi
fi

wait $GETH_PID
