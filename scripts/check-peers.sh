#!/bin/bash
# Script để kiểm tra peers của các nodes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

NODE_NUM=${1:-"all"}

check_node_peers() {
    local NODE_NAME=$1
    local DATADIR=$2
    local RPC_PORT=$3
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 Checking $NODE_NAME peers..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Check if node is running by trying to attach
    if ! ./build/bin/geth attach --exec "true" --datadir "$DATADIR" >/dev/null 2>&1; then
        echo "❌ $NODE_NAME is not running or not accessible"
        echo ""
        return
    fi
    
    # Get peer count
    PEER_COUNT=$(./build/bin/geth attach --exec "net.peerCount" --datadir "$DATADIR" 2>/dev/null | tr -d '\n' | grep -oE '[0-9]+' || echo "0")
    
    echo "🔗 Peer Count: $PEER_COUNT"
    echo ""
    
    if [ "$PEER_COUNT" = "0" ]; then
        echo "⚠️  No peers connected"
    else
        echo "✅ Connected peers:"
        # Get peer details
        PEERS=$(./build/bin/geth attach --exec "admin.peers" --datadir "$DATADIR" 2>/dev/null)
        echo "$PEERS" | head -20
    fi
    
    echo ""
    
    # Get node info
    NODE_INFO=$(./build/bin/geth attach --exec "admin.nodeInfo" --datadir "$DATADIR" 2>/dev/null)
    ENODE=$(echo "$NODE_INFO" | grep -oE 'enode://[^"]+' | head -1)
    
    if [ -n "$ENODE" ]; then
        echo "📍 Node Enode: $ENODE"
    fi
    
    echo ""
}

# Check all nodes or specific node
if [ "$NODE_NUM" = "all" ] || [ "$NODE_NUM" = "1" ]; then
    check_node_peers "Node 1 (Validator 1)" "${HOME}/local-testnet-node1" 8546
fi

if [ "$NODE_NUM" = "all" ] || [ "$NODE_NUM" = "2" ]; then
    check_node_peers "Node 2 (Validator 2)" "${HOME}/local-testnet-node2" 8548
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💡 Usage:"
echo "   ./scripts/check-peers.sh        # Check all nodes"
echo "   ./scripts/check-peers.sh 1      # Check Node 1 only"
echo "   ./scripts/check-peers.sh 2      # Check Node 2 only"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

