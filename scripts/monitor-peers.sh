#!/bin/bash
# Script để monitor peers của các nodes trong real-time

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

NODE_NUM=${1:-"all"}
INTERVAL=${2:-3}

check_peers() {
    local NODE_NAME=$1
    local DATADIR=$2
    
    # Get peer count
    PEER_COUNT=$(./build/bin/geth attach --exec "net.peerCount" --datadir "$DATADIR" 2>/dev/null | tr -d '\n' | grep -oE '[0-9]+' || echo "0")
    
    if [ "$PEER_COUNT" = "0" ]; then
        echo "❌ $NODE_NAME: 0 peers"
    else
        echo "✅ $NODE_NAME: $PEER_COUNT peer(s)"
    fi
}

echo "🔍 Monitoring peers (Press Ctrl+C to stop)"
echo "   Interval: ${INTERVAL}s"
echo ""

while true; do
    clear
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 Peer Status - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    if [ "$NODE_NUM" = "all" ] || [ "$NODE_NUM" = "1" ]; then
        check_peers "Node 1" "${HOME}/local-testnet-node1"
    fi
    
    if [ "$NODE_NUM" = "all" ] || [ "$NODE_NUM" = "2" ]; then
        check_peers "Node 2" "${HOME}/local-testnet-node2"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Press Ctrl+C to stop"
    
    sleep "$INTERVAL"
done

