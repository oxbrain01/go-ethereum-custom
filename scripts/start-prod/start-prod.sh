#!/bin/bash
# Script to start Geth with production-like configuration
# Uses config.toml file for configuration (production-style)

set -e

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

# Default ports (can be overridden in config.toml)
HTTP_PORT=8545
WS_PORT=8546
P2P_PORT=30303
AUTH_PORT=8551

echo "🚀 Starting Geth with Production Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📂 Production directory: $PROD_DIR"
echo "📁 Data directory: $DATADIR"
echo "📄 Config file: $CONFIG_FILE"
echo ""

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

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Configuration Summary:"
echo "   • Production directory: $PROD_DIR"
echo "   • Config file: $CONFIG_FILE"
echo "   • Data directory: $DATADIR"
echo "   • Network: Ethereum Mainnet (default)"
echo "   • Cache: 4096 MB (production default)"
echo ""
echo "💡 All files are stored in: $PROD_DIR"
echo "💡 To customize settings, edit: $CONFIG_FILE"
echo "💡 To regenerate config, delete it and run this script again"
echo "💡 To clean up, delete the entire directory: $PROD_DIR"
echo ""
echo "💡 To stop, press Ctrl+C"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Trap signals for graceful shutdown
trap 'echo ""; echo "🛑 Shutting down Geth..."; exit 0' INT TERM

# Start geth with config file
echo "🚀 Starting Geth..."
echo ""

"$GETH_BINARY" --config "$CONFIG_FILE"

