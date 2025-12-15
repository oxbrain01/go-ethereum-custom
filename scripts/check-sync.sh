#!/bin/bash
# Script để kiểm tra đồng bộ giữa 2 nodes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

NODE1_DATADIR="${HOME}/local-testnet-node1"
NODE2_DATADIR="${HOME}/local-testnet-node2"

echo "📊 Checking node synchronization..."
echo ""

# Get block numbers
NODE1_BLOCK=$(./build/bin/geth attach --exec "eth.blockNumber" --datadir "$NODE1_DATADIR" 2>/dev/null | tr -d '\n' | grep -oE '[0-9]+' || echo "0")
NODE2_BLOCK=$(./build/bin/geth attach --exec "eth.blockNumber" --datadir "$NODE2_DATADIR" 2>/dev/null | tr -d '\n' | grep -oE '[0-9]+' || echo "0")

# Get peer counts
NODE1_PEERS=$(./build/bin/geth attach --exec "admin.peers.length" --datadir "$NODE1_DATADIR" 2>/dev/null | tr -d '\n' | grep -oE '[0-9]+' || echo "0")
NODE2_PEERS=$(./build/bin/geth attach --exec "admin.peers.length" --datadir "$NODE2_DATADIR" 2>/dev/null | tr -d '\n' | grep -oE '[0-9]+' || echo "0")

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Node 1 (Validator 1):"
echo "  Block Number: $NODE1_BLOCK"
echo "  Peer Count: $NODE1_PEERS"
echo ""
echo "Node 2 (Validator 2):"
echo "  Block Number: $NODE2_BLOCK"
echo "  Peer Count: $NODE2_PEERS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check synchronization
if [ "$NODE1_PEERS" = "0" ] || [ "$NODE2_PEERS" = "0" ]; then
    echo "❌ Nodes are NOT connected!"
    echo "💡 Run: ./scripts/connect-and-unlock.sh"
elif [ "$NODE1_BLOCK" = "$NODE2_BLOCK" ]; then
    if [ "$NODE1_BLOCK" = "0" ]; then
        echo "⚠️  Both nodes at block 0 - validators may not be mining"
        echo "💡 Make sure validators are unlocked:"
        echo "   ./scripts/connect-and-unlock.sh"
    else
        echo "✅ Nodes are synchronized at block $NODE1_BLOCK"
    fi
else
    DIFF=$((NODE1_BLOCK > NODE2_BLOCK ? NODE1_BLOCK - NODE2_BLOCK : NODE2_BLOCK - NODE1_BLOCK))
    echo "⚠️  Nodes are NOT synchronized (difference: $DIFF blocks)"
    echo "💡 Wait a moment for sync, or check: ./scripts/check-peers.sh"
fi

echo ""

