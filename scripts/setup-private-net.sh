#!/bin/bash
# Script setup private network với Clique consensus

NETWORKID=1337
DATADIR="${HOME}/local-testnet"
GENESIS="genesis-example.json"

echo "🔧 Setting up private network..."
echo "📁 Data directory: $DATADIR"
echo ""

# Kiểm tra xem geth đã được build chưa
if [ ! -f "./build/bin/geth" ]; then
    echo "❌ Geth not found. Building..."
    make geth
fi

# Kiểm tra genesis file
if [ ! -f "$GENESIS" ]; then
    echo "❌ Genesis file not found: $GENESIS"
    echo "Please create genesis.json file first"
    exit 1
fi

# Tạo data directory nếu chưa có
mkdir -p "$DATADIR"

# Tạo account mới
echo "📝 Creating new account..."
echo "Please enter a password for the new account:"
./build/bin/geth --datadir "$DATADIR" account new

# Initialize genesis
echo ""
echo "🔨 Initializing genesis block..."
./build/bin/geth --datadir "$DATADIR" init "$GENESIS"

echo ""
echo "✅ Setup complete!"
echo ""
echo "To start the node, run:"
echo "  ./start-node.sh"
echo ""
echo "Or manually:"
echo "  ./build/bin/geth --datadir $DATADIR --networkid $NETWORKID --http --http.port 8546 console"
