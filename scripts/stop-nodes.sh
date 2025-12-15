#!/bin/bash
# Script để stop các geth nodes
# Usage: ./stop-nodes.sh [all|1|2]

NODE_NUM=${1:-"all"}

stop_node() {
    local NODE_NAME=$1
    local DATADIR=$2
    
    echo "🛑 Stopping $NODE_NAME..."
    
    # Find process by datadir
    PID=$(pgrep -f "geth.*$DATADIR" | head -1)
    
    if [ -z "$PID" ]; then
        echo "   ℹ️  $NODE_NAME is not running"
        return
    fi
    
    echo "   Found process: $PID"
    
    # Try graceful shutdown first (SIGTERM)
    kill -TERM "$PID" 2>/dev/null
    
    # Wait a bit
    sleep 2
    
    # Check if still running
    if kill -0 "$PID" 2>/dev/null; then
        echo "   ⚠️  Force killing..."
        kill -9 "$PID" 2>/dev/null
    fi
    
    echo "   ✅ $NODE_NAME stopped"
}

if [ "$NODE_NUM" = "all" ]; then
    echo "🛑 Stopping all Geth nodes..."
    echo ""
    stop_node "Node 1" "${HOME}/local-testnet-node1"
    stop_node "Node 2" "${HOME}/local-testnet-node2"
    echo ""
    echo "✅ Done"
elif [ "$NODE_NUM" = "1" ]; then
    stop_node "Node 1" "${HOME}/local-testnet-node1"
elif [ "$NODE_NUM" = "2" ]; then
    stop_node "Node 2" "${HOME}/local-testnet-node2"
else
    echo "❌ Invalid node number. Use: all, 1, or 2"
    echo "Usage: ./stop-nodes.sh [all|1|2]"
    exit 1
fi

