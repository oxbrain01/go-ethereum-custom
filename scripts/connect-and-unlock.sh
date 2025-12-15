#!/bin/bash
# Script để kết nối Node 2 với Node 1 và unlock validator accounts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

NODE1_DATADIR="${HOME}/local-testnet-node1"
NODE2_DATADIR="${HOME}/local-testnet-node2"

echo "🔗 Connecting Node 2 to Node 1 and unlocking validators..."
echo ""

# Step 1: Get Node 1's enode
echo "1️⃣  Getting Node 1's enode address..."
NODE1_ENODE=$(./build/bin/geth attach --exec "admin.nodeInfo.enode" --datadir "$NODE1_DATADIR" 2>/dev/null | tr -d '"' | tr -d '\n' | grep -oE 'enode://[^"]+' || echo "")

if [ -z "$NODE1_ENODE" ]; then
    echo "   ❌ Could not get Node 1's enode. Is Node 1 running?"
    exit 1
fi

echo "   ✅ Node 1 enode: $NODE1_ENODE"
echo "$NODE1_ENODE" > "${NODE1_DATADIR}/enode.txt"

# Step 2: Connect Node 2 to Node 1
echo ""
echo "2️⃣  Connecting Node 2 to Node 1..."
CONNECT_RESULT=$(./build/bin/geth attach --exec "admin.addPeer('$NODE1_ENODE')" --datadir "$NODE2_DATADIR" 2>/dev/null | tr -d '\n')

if echo "$CONNECT_RESULT" | grep -q "true"; then
    echo "   ✅ Node 2 connected to Node 1"
else
    echo "   ⚠️  Connection result: $CONNECT_RESULT"
    echo "   (May already be connected)"
fi

# Step 3: Unlock Node 1 validator
echo ""
echo "3️⃣  Unlocking Node 1 validator account..."
NODE1_VALIDATOR=$(cat "${NODE1_DATADIR}/validator_address.txt" 2>/dev/null | tr -d '\n')
NODE1_PASSWORD=$(cat "${NODE1_DATADIR}/password.txt" 2>/dev/null || echo "validator123")

if [ -n "$NODE1_VALIDATOR" ]; then
    # Try via RPC first
    UNLOCK_RESULT=$(curl -s -X POST "http://localhost:8546" \
      -H "Content-Type: application/json" \
      -d "{
        \"jsonrpc\":\"2.0\",
        \"method\":\"personal_unlockAccount\",
        \"params\":[\"$NODE1_VALIDATOR\", \"$NODE1_PASSWORD\", 0],
        \"id\":1
      }" 2>/dev/null)
    
    if echo "$UNLOCK_RESULT" | grep -q '"result":true'; then
        echo "   ✅ Node 1 validator unlocked via RPC"
    else
        echo "   ⚠️  Personal API not available. Unlock manually in Node 1 console:"
        echo "      personal.unlockAccount('$NODE1_VALIDATOR', '$NODE1_PASSWORD', 0)"
    fi
else
    echo "   ⚠️  Node 1 validator address not found"
fi

# Step 4: Unlock Node 2 validator
echo ""
echo "4️⃣  Unlocking Node 2 validator account..."
NODE2_VALIDATOR=$(cat "${NODE2_DATADIR}/validator_address.txt" 2>/dev/null | tr -d '\n')
NODE2_PASSWORD=$(cat "${NODE2_DATADIR}/password.txt" 2>/dev/null || echo "validator123")

if [ -n "$NODE2_VALIDATOR" ]; then
    # Try via RPC first
    UNLOCK_RESULT=$(curl -s -X POST "http://localhost:8548" \
      -H "Content-Type: application/json" \
      -d "{
        \"jsonrpc\":\"2.0\",
        \"method\":\"personal_unlockAccount\",
        \"params\":[\"$NODE2_VALIDATOR\", \"$NODE2_PASSWORD\", 0],
        \"id\":1
      }" 2>/dev/null)
    
    if echo "$UNLOCK_RESULT" | grep -q '"result":true'; then
        echo "   ✅ Node 2 validator unlocked via RPC"
    else
        echo "   ⚠️  Personal API not available. Unlock manually in Node 2 console:"
        echo "      personal.unlockAccount('$NODE2_VALIDATOR', '$NODE2_PASSWORD', 0)"
    fi
else
    echo "   ⚠️  Node 2 validator address not found"
fi

# Step 5: Check peers
echo ""
echo "5️⃣  Checking peer connections..."
echo ""
echo "Node 1 peers:"
NODE1_PEERS=$(./build/bin/geth attach --exec "admin.peers.length" --datadir "$NODE1_DATADIR" 2>/dev/null | tr -d '\n' | grep -oE '[0-9]+' || echo "0")
echo "   Peer count: $NODE1_PEERS"

echo ""
echo "Node 2 peers:"
NODE2_PEERS=$(./build/bin/geth attach --exec "admin.peers.length" --datadir "$NODE2_DATADIR" 2>/dev/null | tr -d '\n' | grep -oE '[0-9]+' || echo "0")
echo "   Peer count: $NODE2_PEERS"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$NODE1_PEERS" -gt 0 ] && [ "$NODE2_PEERS" -gt 0 ]; then
    echo "✅ Both nodes are connected!"
    echo "💡 Check block numbers:"
    echo "   Node 1: ./build/bin/geth attach --exec 'eth.blockNumber' --datadir $NODE1_DATADIR"
    echo "   Node 2: ./build/bin/geth attach --exec 'eth.blockNumber' --datadir $NODE2_DATADIR"
else
    echo "⚠️  Nodes may not be fully connected yet"
    echo "💡 Run this script again or check manually:"
    echo "   ./scripts/check-peers.sh"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

