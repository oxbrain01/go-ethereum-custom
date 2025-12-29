#!/bin/bash
# Script to start Geth with production-like configuration
# Uses config.toml file for configuration (production-style)

set -e

# Parse command line arguments
QUIET=false
VERBOSITY=3  # Default: INFO level (3), 0=silent, 1=error, 2=warn, 3=info, 4=debug, 5=detail

while [[ $# -gt 0 ]]; do
    case $1 in
        --quiet|-q)
            QUIET=true
            VERBOSITY=2  # WARN level to suppress INFO logs (including Brain-log)
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
            echo "  --quiet, -q          Suppress INFO logs (sets verbosity to 2, hides Brain-log messages)"
            echo "  --verbosity, -v NUM  Set log verbosity (0=silent, 1=error, 2=warn, 3=info, 4=debug, 5=detail)"
            echo "                       Default: 3 (info)"
            echo "  --help, -h           Show this help message"
            echo ""
            echo "Examples:"
            echo "  $(basename "$0")                  # Start with default verbosity (INFO logs)"
            echo "  $(basename "$0") --quiet          # Start with WARN level (no INFO/Brain-log)"
            echo "  $(basename "$0") -v 2             # Start with WARN level (same as --quiet)"
            echo "  $(basename "$0") -v 1             # Start with ERROR level only"
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            echo "   Use --help for usage information"
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Script is in scripts/start-prod/, so go up 2 levels to reach project root
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

# Verify we're in the project root
if [ ! -f "Makefile" ] || [ ! -f "go.mod" ]; then
    echo "❌ Error: Could not find project root (Makefile or go.mod not found)"
    echo "   Current directory: $(pwd)"
    echo "   Script directory: $SCRIPT_DIR"
    echo "   Expected project root: $PROJECT_ROOT"
    exit 1
fi

# All directories relative to scripts/start-prod for easy control
PROD_DIR="$SCRIPT_DIR"
DATADIR="${PROD_DIR}/data"
CONFIG_FILE="${PROD_DIR}/config.toml"
GENESIS_FILE="${PROD_DIR}/genesis.json"
PASSWORD_FILE="${PROD_DIR}/.password"
VALIDATOR_ADDRESS="0x356981ee849c96fC40e78B0B22715345E57746fb"
SCRIPT_LOCK_FILE="${PROD_DIR}/.start-prod.lock"

# Default ports (can be overridden in config.toml)
# Using different ports to avoid conflict with Anvil (8545)
HTTP_PORT=8547
WS_PORT=8548
P2P_PORT=30304
AUTH_PORT=8552

echo "🚀 Starting Geth with Production Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📂 Production directory: $PROD_DIR"
echo "📁 Data directory: $DATADIR"
echo "📄 Config file: $CONFIG_FILE"
echo ""

# Check for script lock file to prevent multiple instances
if [ -f "$SCRIPT_LOCK_FILE" ]; then
    LOCK_PID=$(cat "$SCRIPT_LOCK_FILE" 2>/dev/null)
    if [ ! -z "$LOCK_PID" ] && ps -p "$LOCK_PID" > /dev/null 2>&1; then
        echo "⚠️  Script is already running (PID: $LOCK_PID)"
        echo "   If this is incorrect, delete the lock file: $SCRIPT_LOCK_FILE"
        echo "   Or wait for the existing instance to finish"
        exit 1
    else
        echo "⚠️  Found stale lock file, removing it..."
        rm -f "$SCRIPT_LOCK_FILE"
    fi
fi

# Create lock file with current PID
echo $$ > "$SCRIPT_LOCK_FILE"

# Check for and stop existing geth processes using the same datadir or config
echo "🔍 Checking for existing geth processes..."

# Check for datadir lock file (indicates geth is using this datadir)
LOCK_FILE="${DATADIR}/geth/LOCK"
if [ -f "$LOCK_FILE" ]; then
    echo "⚠️  Found lock file at $LOCK_FILE - geth may be running"
    # Try to find the process
    EXISTING_GETH=$(ps aux | grep -E "[g]eth.*--config.*config.toml|[g]eth.*--datadir.*$DATADIR" | awk '{print $2}' | tr '\n' ' ')
    if [ ! -z "$EXISTING_GETH" ]; then
        echo "   Found geth process(es): $EXISTING_GETH"
    fi
fi

# Find all geth processes that might be using our config or datadir
EXISTING_GETH=$(ps aux | grep -E "[g]eth.*--config.*config.toml|[g]eth.*--datadir.*start-prod" | awk '{print $2}' | tr '\n' ' ')

if [ ! -z "$EXISTING_GETH" ]; then
    echo "⚠️  Found existing geth process(es): $EXISTING_GETH"
    echo "🛑 Stopping existing processes..."
    for pid in $EXISTING_GETH; do
        if ps -p "$pid" > /dev/null 2>&1; then
            echo "   Stopping PID $pid..."
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
    sleep 3
    # Force kill if still running
    for pid in $EXISTING_GETH; do
        if ps -p "$pid" > /dev/null 2>&1; then
            echo "   Force killing PID $pid..."
            kill -9 "$pid" 2>/dev/null || true
        fi
    done
    sleep 2
    # Remove lock file if it still exists
    if [ -f "$LOCK_FILE" ]; then
        echo "   Removing stale lock file..."
        rm -f "$LOCK_FILE"
    fi
    echo "✅ Existing processes stopped"
    echo ""
fi

# Check for and stop existing beacon simulator processes
echo "🔍 Checking for existing beacon simulator processes..."
BEACON_SCRIPT="${PROJECT_ROOT}/scripts/beacon-simulator-fixed.py"
BEACON_LOCK_FILE="/tmp/beacon-simulator.lock"
if [ -f "$BEACON_SCRIPT" ]; then
    # Find all beacon simulator processes using the same script
    EXISTING_BEACON=$(ps aux | grep -E "[p]ython.*beacon-simulator-fixed.py" | awk '{print $2}' | tr '\n' ' ')
    if [ ! -z "$EXISTING_BEACON" ]; then
        echo "⚠️  Found existing beacon simulator process(es): $EXISTING_BEACON"
        echo "🛑 Stopping existing beacon simulators..."
        for pid in $EXISTING_BEACON; do
            if ps -p "$pid" > /dev/null 2>&1; then
                echo "   Stopping beacon simulator PID $pid..."
                kill -TERM "$pid" 2>/dev/null || true
            fi
        done
        sleep 2
        # Force kill if still running
        for pid in $EXISTING_BEACON; do
            if ps -p "$pid" > /dev/null 2>&1; then
                echo "   Force killing beacon simulator PID $pid..."
                kill -9 "$pid" 2>/dev/null || true
            fi
        done
        sleep 1
        # Remove lock file if it exists
        if [ -f "$BEACON_LOCK_FILE" ]; then
            echo "   Removing stale beacon simulator lock file..."
            rm -f "$BEACON_LOCK_FILE"
        fi
        echo "✅ Existing beacon simulators stopped"
        echo ""
    elif [ -f "$BEACON_LOCK_FILE" ]; then
        # Lock file exists but no process found - remove stale lock
        echo "⚠️  Found stale beacon simulator lock file, removing it..."
        rm -f "$BEACON_LOCK_FILE"
        echo ""
    fi
fi

# Also check for processes using the same ports
echo "🔍 Checking for processes using the same ports..."
PORT_CONFLICTS=false
if command -v lsof > /dev/null 2>&1; then
    if lsof -ti:$HTTP_PORT > /dev/null 2>&1; then
        echo "⚠️  Port $HTTP_PORT (HTTP) is in use"
        PORT_CONFLICTS=true
    fi
    if lsof -ti:$WS_PORT > /dev/null 2>&1; then
        echo "⚠️  Port $WS_PORT (WebSocket) is in use"
        PORT_CONFLICTS=true
    fi
    if lsof -ti:$AUTH_PORT > /dev/null 2>&1; then
        echo "⚠️  Port $AUTH_PORT (Auth) is in use"
        PORT_CONFLICTS=true
    fi

    if [ "$PORT_CONFLICTS" = true ]; then
        echo "🛑 Stopping processes using these ports..."
        lsof -ti:$HTTP_PORT 2>/dev/null | xargs kill -TERM 2>/dev/null || true
        lsof -ti:$WS_PORT 2>/dev/null | xargs kill -TERM 2>/dev/null || true
        lsof -ti:$AUTH_PORT 2>/dev/null | xargs kill -TERM 2>/dev/null || true
        sleep 2
        # Force kill if still running
        lsof -ti:$HTTP_PORT 2>/dev/null | xargs kill -9 2>/dev/null || true
        lsof -ti:$WS_PORT 2>/dev/null | xargs kill -9 2>/dev/null || true
        lsof -ti:$AUTH_PORT 2>/dev/null | xargs kill -9 2>/dev/null || true
        sleep 1
        echo "✅ Port conflicts resolved"
        echo ""
    fi
fi

# Check if geth is built
GETH_BINARY="./build/bin/geth"
if [ ! -f "$GETH_BINARY" ]; then
    echo "❌ Geth not found at: $GETH_BINARY"
    echo "📦 Building geth..."
    echo "   Working directory: $(pwd)"
    
    if [ ! -f "Makefile" ]; then
        echo "❌ Makefile not found in current directory"
        exit 1
    fi
    
    make geth
    BUILD_EXIT_CODE=$?
    if [ $BUILD_EXIT_CODE -ne 0 ]; then
        echo "❌ Failed to build geth (exit code: $BUILD_EXIT_CODE)"
        echo "   Make sure you're in the project root and have Go installed"
        exit 1
    fi
    
    if [ ! -f "$GETH_BINARY" ]; then
        echo "❌ Build completed but geth binary not found at: $GETH_BINARY"
        exit 1
    fi
    echo "✅ Geth built successfully"
fi

# Create data directory if it doesn't exist
if [ ! -d "$DATADIR" ]; then
    echo "📁 Creating data directory: $DATADIR"
    mkdir -p "$DATADIR"
fi

# Create password file for validator if it doesn't exist
if [ ! -f "$PASSWORD_FILE" ]; then
    echo "🔐 Creating password file for validator..."
    echo "validator123" > "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"
    echo "✅ Password file created (default password: validator123)"
    echo "   ⚠️  Change password in production!"
    echo ""
fi

# Ensure validator account exists with correct private key
KEYSTORE_DIR="${DATADIR}/keystore"
VALIDATOR_PRIVATE_KEY="0x9de1394869030ea18ee8930c533722d71f6990b5576dee849b9c23b7d094c186"

# Check if validator account exists
ACCOUNT_EXISTS=false
if [ -d "$KEYSTORE_DIR" ]; then
    # Normalize validator address to lowercase for comparison
    VALIDATOR_ADDRESS_LOWER=$(echo "$VALIDATOR_ADDRESS" | tr '[:upper:]' '[:lower:]')
    for keystore_file in "$KEYSTORE_DIR"/*; do
        if [ -f "$keystore_file" ]; then
            # Extract address from keystore filename or content
            FILE_ADDRESS=$(basename "$keystore_file" | grep -oE '[a-fA-F0-9]{40}' | head -1)
            if [ ! -z "$FILE_ADDRESS" ]; then
                # Normalize to lowercase for comparison
                FILE_ADDRESS_LOWER=$(echo "$FILE_ADDRESS" | tr '[:upper:]' '[:lower:]')
                if [ "0x${FILE_ADDRESS_LOWER}" = "$VALIDATOR_ADDRESS_LOWER" ]; then
                    ACCOUNT_EXISTS=true
                    break
                fi
            fi
        fi
    done
fi

# Import validator account if it doesn't exist
if [ "$ACCOUNT_EXISTS" = false ]; then
    echo "🔑 Importing validator account with private key..."
    echo "validator123" | "$GETH_BINARY" --datadir "$DATADIR" account import <(echo "$VALIDATOR_PRIVATE_KEY") --password <(echo "validator123") 2>/dev/null || {
        # If import fails, try creating new account (will have different address)
        echo "⚠️  Could not import validator account"
        echo "   Creating new account instead..."
        echo "validator123" | "$GETH_BINARY" --datadir "$DATADIR" account new --password <(echo "validator123") > /dev/null 2>&1
        CREATED_ADDRESS=$(ls "$KEYSTORE_DIR" 2>/dev/null | head -1 | grep -oE '[a-fA-F0-9]{40}' | head -1)
        if [ ! -z "$CREATED_ADDRESS" ]; then
            echo "   ⚠️  New account created: 0x$CREATED_ADDRESS"
            echo "   ⚠️  Update genesis.json extradata with this address!"
            VALIDATOR_ADDRESS="0x$CREATED_ADDRESS"
        fi
    }
    if [ "$ACCOUNT_EXISTS" = false ] && [ -d "$KEYSTORE_DIR" ] && [ -n "$(ls -A "$KEYSTORE_DIR" 2>/dev/null)" ]; then
        echo "✅ Validator account ready"
    fi
    echo ""
fi

# Initialize genesis block if database is empty or if geth/chaindata doesn't exist
if [ ! -d "$DATADIR/geth/chaindata" ]; then
    if [ ! -f "$GENESIS_FILE" ]; then
        echo "❌ Genesis file not found: $GENESIS_FILE"
        echo "   Please create a genesis.json file first"
        exit 1
    fi
    echo "🔨 Initializing new blockchain from genesis..."
    echo "   Genesis file: $GENESIS_FILE"
    echo "   Data directory: $DATADIR"
    
    # Remove any partial/corrupted data
    if [ -d "$DATADIR/geth" ]; then
        echo "   Cleaning up partial data..."
        rm -rf "$DATADIR/geth/chaindata" 2>/dev/null || true
        rm -rf "$DATADIR/geth/chaindata/ancient" 2>/dev/null || true
    fi
    
    "$GETH_BINARY" --datadir "$DATADIR" init "$GENESIS_FILE"
    INIT_EXIT_CODE=$?
    if [ $INIT_EXIT_CODE -ne 0 ]; then
        echo "❌ Failed to initialize genesis block (exit code: $INIT_EXIT_CODE)"
        exit 1
    fi
    echo "✅ Genesis block initialized successfully"
    echo ""
fi

# Create config.toml if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    echo "📝 Creating default production config.toml..."
    echo "   You can customize this file: $CONFIG_FILE"
    echo ""
    
    # Generate a default config using dumpconfig
    "$GETH_BINARY" \
        --datadir "$DATADIR" \
        --http \
        --http.addr "0.0.0.0" \
        --http.port "$HTTP_PORT" \
        --http.api "eth,net,web3,engine,admin" \
        --ws \
        --ws.addr "0.0.0.0" \
        --ws.port "$WS_PORT" \
        --ws.api "eth,net,web3,engine,admin" \
        --authrpc.addr "0.0.0.0" \
        --authrpc.port "$AUTH_PORT" \
        --authrpc.vhosts "*" \
        --cache 4096 \
        --cache.database 50 \
        --cache.trie 25 \
        --cache.gc 25 \
        --cache.snapshot 10 \
        dumpconfig > "$CONFIG_FILE" 2>/dev/null || {
        # If dumpconfig fails, create a minimal config
        echo "⚠️  Could not generate config automatically. Creating minimal config..."
        cat > "$CONFIG_FILE" <<EOF
# Geth Production Configuration
# This file can be customized for your production setup

[Eth]
SyncMode = "snap"
NoPruning = false
NoPrefetch = false
TxLookupLimit = 2350000

[Node]
DataDir = "$DATADIR"
IPCPath = "geth.ipc"
HTTPHost = "0.0.0.0"
HTTPPort = $HTTP_PORT
HTTPModules = ["eth", "net", "web3", "engine", "admin"]
WSHost = "0.0.0.0"
WSPort = $WS_PORT
WSModules = ["eth", "net", "web3", "engine", "admin"]
AuthAddr = "0.0.0.0"
AuthPort = $AUTH_PORT
AuthVhosts = ["*"]

[Node.P2P]
MaxPeers = 50
NoDiscovery = false

[Eth.Miner]
GasCeil = 30000000
Recommit = 3000000000

[Eth.Cache]
Cache = 4096
CacheDatabase = 50
CacheTrie = 25
CacheGCFull = 25
CacheSnapshot = 10
EOF
    }
    echo "✅ Created config file: $CONFIG_FILE"
    echo ""
fi

# Verify config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config file not found: $CONFIG_FILE"
    exit 1
fi

# Read chain ID from genesis file if it exists
CHAIN_ID="N/A"
if [ -f "$GENESIS_FILE" ]; then
    CHAIN_ID=$(grep -o '"chainId"[[:space:]]*:[[:space:]]*[0-9]*' "$GENESIS_FILE" | grep -o '[0-9]*' | head -1)
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Configuration Summary:"
echo "   • Production directory: $PROD_DIR"
echo "   • Config file: $CONFIG_FILE"
echo "   • Data directory: $DATADIR"
echo "   • Genesis file: $GENESIS_FILE"
echo "   • Network: Custom Blockchain (NetworkId = 2026, ChainId = $CHAIN_ID)"
echo "   • Sync Mode: Snap (fast sync with full state)"
echo "   • History Mode: All (full historical data)"
echo "   • Cache: 4096 MB (production default)"
if [ "$QUIET" = true ]; then
    echo "   • Log Verbosity: $VERBOSITY (WARN - Brain-log messages suppressed)"
else
    echo "   • Log Verbosity: $VERBOSITY (INFO - all logs including Brain-log)"
fi
echo ""
echo "🔌 Enabled APIs:"
echo "   • HTTP APIs: eth, net, web3, engine, admin, debug, txpool, miner"
echo "   • WebSocket APIs: eth, net, web3, engine, admin, debug, txpool, miner"
echo "   • GraphQL: Enabled (via --graphql flag)"
echo "   • Engine API: Enabled (port $AUTH_PORT)"
echo ""
echo "🌐 Network Features:"
echo "   • P2P Discovery: Disabled (private network)"
echo "   • Bootstrap Nodes: None (standalone blockchain)"
echo "   • Max Peers: 50 (for future connections)"
echo ""
echo "⚡ Ethereum Features:"
echo "   • Blob Transactions: Enabled (MaxBlobsPerBlock = 6)"
echo "   • Transaction Pool: Full configuration"
echo "   • State Pruning: Enabled (optimized storage)"
echo "   • Full History: Enabled (all blocks & states)"
echo "   • All Hard Forks: Enabled from genesis"
echo ""
echo "💡 All files are stored in: $PROD_DIR"
echo "💡 To customize settings, edit: $CONFIG_FILE"
echo "💡 To regenerate config, delete it and run this script again"
echo "💡 To clean up, delete the entire directory: $PROD_DIR"
echo ""
echo "💡 To stop, press Ctrl+C"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Global variables for cleanup
GETH_PID=""
BEACON_PID=""

# Cleanup function
cleanup() {
    echo ""
    echo "🛑 Shutting down..."
    if [ ! -z "$BEACON_PID" ]; then
        kill "$BEACON_PID" 2>/dev/null || true
    fi
    if [ ! -z "$GETH_PID" ]; then
        kill "$GETH_PID" 2>/dev/null || true
    fi
    rm -f "$SCRIPT_LOCK_FILE"
    exit 0
}

# Trap signals for graceful shutdown
trap cleanup INT TERM EXIT

# Start geth with config file
echo "🚀 Starting Geth..."
echo ""

# Start geth with custom blockchain configuration
# Network ID is set in config.toml (2026)
# Genesis block should already be initialized
# Note: --mine flag doesn't work with Clique+Beacon, we need SimulatedBeacon or Engine API
"$GETH_BINARY" \
    --config "$CONFIG_FILE" \
    --verbosity "$VERBOSITY" \
    --graphql \
    --unlock "$VALIDATOR_ADDRESS" \
    --password "$PASSWORD_FILE" \
    --allow-insecure-unlock \
    --miner.etherbase "$VALIDATOR_ADDRESS" &
    
GETH_PID=$!

# Wait for geth to start and state to be ready
echo "⏳ Waiting for node to be ready..."
sleep 3

# Wait for node to be fully ready and state to be accessible
echo "⏳ Waiting for state database to be ready..."
for i in {1..30}; do
    # Check if node is responding
    BLOCK_NUM=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        http://localhost:$HTTP_PORT 2>/dev/null | grep -oE '"result":"0x[0-9a-f]+"' | cut -d'"' -f4)
    
    if [ ! -z "$BLOCK_NUM" ]; then
        # Check if we can get genesis block (state should be ready)
        GENESIS_STATE=$(curl -s -X POST -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["0x0", false],"id":1}' \
            http://localhost:$HTTP_PORT 2>/dev/null | grep -oE '"stateRoot":"0x[0-9a-f]+"' | cut -d'"' -f4)
        
        if [ ! -z "$GENESIS_STATE" ]; then
            echo "✅ Node and state database ready"
            break
        fi
    fi
    
    if [ $i -eq 30 ]; then
        echo "⚠️  Node might not be fully ready, but continuing..."
    else
        sleep 1
    fi
done

# Check if JWT secret exists (needed for Engine API)
JWT_SECRET_PATH="${DATADIR}/geth/jwtsecret"
if [ ! -f "$JWT_SECRET_PATH" ]; then
    echo "⚠️  JWT secret not found. Engine API might not work."
    echo "   Blocks will need to be created manually via Engine API"
fi

# Try to start Python beacon simulator if available
BEACON_SCRIPT="${PROJECT_ROOT}/scripts/beacon-simulator-fixed.py"
if [ -f "$BEACON_SCRIPT" ] && command -v python3 > /dev/null 2>&1; then
    echo "🔷 Starting Python beacon simulator for automatic block creation..."
    echo "   Script: $BEACON_SCRIPT"
    echo "   JWT Secret: $JWT_SECRET_PATH"
    
    # Wait a bit more for JWT secret to be created
    for i in {1..10}; do
        if [ -f "$JWT_SECRET_PATH" ]; then
            break
        fi
        sleep 1
    done
    
    if [ -f "$JWT_SECRET_PATH" ]; then
        # Start beacon simulator in background (show output for debugging)
        cd "$PROJECT_ROOT" || exit 1
        python3 "$BEACON_SCRIPT" &
        BEACON_PID=$!
        echo "✅ Beacon simulator started (PID: $BEACON_PID)"
        echo ""
        echo "💡 Blocks will be created automatically every 5 seconds"
        echo "💡 To stop beacon simulator: kill $BEACON_PID"
        echo ""
    else
        echo "⚠️  JWT secret not found at $JWT_SECRET_PATH"
        echo "   Beacon simulator cannot start without JWT secret"
        echo "   Blocks will NOT be created automatically!"
        echo ""
    fi
else
    echo "⚠️  Python beacon simulator not found or Python3 not installed"
    echo "   Script path: $BEACON_SCRIPT"
    echo "   Blocks will NOT be created automatically!"
    echo "   Install Python3 and run manually:"
    echo "   python3 scripts/beacon-simulator-fixed.py"
    echo ""
fi

# Wait for geth process
wait $GETH_PID

