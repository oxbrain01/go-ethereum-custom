#!/bin/bash
# Script to unlock validators on both nodes after they start
# This ensures Clique consensus can create blocks

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

NODE1_DATADIR="${HOME}/local-testnet-node1"
NODE2_DATADIR="${HOME}/local-testnet-node2"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔓 UNLOCKING VALIDATORS FOR BLOCK MINING"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get validator addresses
NODE1_VALIDATOR=$(cat "${NODE1_DATADIR}/validator_address.txt" 2>/dev/null | tr -d '\n')
NODE2_VALIDATOR=$(cat "${NODE2_DATADIR}/validator_address.txt" 2>/dev/null | tr -d '\n')
PASSWORD="validator123"

if [ -z "$NODE1_VALIDATOR" ] || [ -z "$NODE2_VALIDATOR" ]; then
    echo "❌ Validator addresses not found"
    exit 1
fi

# Check if nodes are running
echo "🔍 Checking if nodes are running..."
NODE1_RUNNING=$(./build/bin/geth attach --exec "eth.blockNumber" --datadir "$NODE1_DATADIR" 2>/dev/null | grep -oE '[0-9]+' || echo "")
NODE2_RUNNING=$(./build/bin/geth attach --exec "eth.blockNumber" --datadir "$NODE2_DATADIR" 2>/dev/null | grep -oE '[0-9]+' || echo "")

if [ -z "$NODE1_RUNNING" ]; then
    echo "❌ Node 1 is not running. Please start it first with: ./scripts/start-node1.sh"
    exit 1
fi

if [ -z "$NODE2_RUNNING" ]; then
    echo "❌ Node 2 is not running. Please start it first with: ./scripts/start-node2.sh"
    exit 1
fi

echo "✅ Both nodes are running"
echo ""

# Unlock Node 1 validator
echo "1️⃣  Unlocking Node 1 validator ($NODE1_VALIDATOR)..."
# Try multiple times as the node might need a moment to be ready
UNLOCK1="unknown"
for i in {1..10}; do
    # Use a more reliable method - pipe the command directly
    UNLOCK_RESULT=$(echo "personal.unlockAccount('$NODE1_VALIDATOR', '$PASSWORD', 0)" | ./build/bin/geth attach --datadir "$NODE1_DATADIR" 2>&1)
    UNLOCK1=$(echo "$UNLOCK_RESULT" | tail -1 | grep -oE 'true|false|Error|undefined|null' || echo "unknown")
    
    # Also check for success in the output
    if echo "$UNLOCK_RESULT" | grep -q "true"; then
        UNLOCK1="true"
    fi
    
    if echo "$UNLOCK1" | grep -qE "true|false"; then
        break
    fi
    if [ $i -lt 10 ]; then
        sleep 1
    fi
done

if echo "$UNLOCK1" | grep -q "true"; then
    echo "   ✅ Node 1 validator unlocked successfully"
elif echo "$UNLOCK1" | grep -q "false"; then
    echo "   ⚠️  Node 1 unlock returned false - trying to verify if already unlocked..."
    # Check if we can sign with this account (better test than balance)
    # Try to get the coinbase to see if it's set
    COINBASE=$(./build/bin/geth attach --exec "eth.coinbase" --datadir "$NODE1_DATADIR" 2>/dev/null | grep -oE '0x[a-fA-F0-9]{40}' || echo "")
    if [ "$COINBASE" = "$NODE1_VALIDATOR" ]; then
        echo "   ✅ Validator is set as coinbase (likely unlocked)"
    else
        echo "   ⚠️  Validator not set as coinbase, trying again..."
        # Force unlock one more time
        echo "personal.unlockAccount('$NODE1_VALIDATOR', '$PASSWORD', 0)" | timeout 5 ./build/bin/geth attach --datadir "$NODE1_DATADIR" 2>&1 | grep -q "true" && echo "   ✅ Unlocked on retry" || echo "   ⚠️  Still having issues"
    fi
else
    echo "   ⚠️  Node 1 unlock result: $UNLOCK1"
    echo "   💡 The account might need to be unlocked manually in the geth console"
fi

# Unlock Node 2 validator
echo ""
echo "2️⃣  Unlocking Node 2 validator ($NODE2_VALIDATOR)..."
# Try multiple times as the node might need a moment to be ready
UNLOCK2="unknown"
for i in {1..10}; do
    # Use a more reliable method - pipe the command directly
    UNLOCK_RESULT=$(echo "personal.unlockAccount('$NODE2_VALIDATOR', '$PASSWORD', 0)" | ./build/bin/geth attach --datadir "$NODE2_DATADIR" 2>&1)
    UNLOCK2=$(echo "$UNLOCK_RESULT" | tail -1 | grep -oE 'true|false|Error|undefined|null' || echo "unknown")
    
    # Also check for success in the output
    if echo "$UNLOCK_RESULT" | grep -q "true"; then
        UNLOCK2="true"
    fi
    
    if echo "$UNLOCK2" | grep -qE "true|false"; then
        break
    fi
    if [ $i -lt 10 ]; then
        sleep 1
    fi
done

if echo "$UNLOCK2" | grep -q "true"; then
    echo "   ✅ Node 2 validator unlocked successfully"
elif echo "$UNLOCK2" | grep -q "false"; then
    echo "   ⚠️  Node 2 unlock returned false - trying to verify if already unlocked..."
    # Check if we can sign with this account (better test than balance)
    # Try to get the coinbase to see if it's set
    COINBASE=$(./build/bin/geth attach --exec "eth.coinbase" --datadir "$NODE2_DATADIR" 2>/dev/null | grep -oE '0x[a-fA-F0-9]{40}' || echo "")
    if [ "$COINBASE" = "$NODE2_VALIDATOR" ]; then
        echo "   ✅ Validator is set as coinbase (likely unlocked)"
    else
        echo "   ⚠️  Validator not set as coinbase, trying again..."
        # Force unlock one more time
        echo "personal.unlockAccount('$NODE2_VALIDATOR', '$PASSWORD', 0)" | timeout 5 ./build/bin/geth attach --datadir "$NODE2_DATADIR" 2>&1 | grep -q "true" && echo "   ✅ Unlocked on retry" || echo "   ⚠️  Still having issues"
    fi
else
    echo "   ⚠️  Node 2 unlock result: $UNLOCK2"
    echo "   💡 The account might need to be unlocked manually in the geth console"
fi

# Check peer connection
echo ""
echo "3️⃣  Checking peer connections..."
PEERS1=$(./build/bin/geth attach --exec "admin.peers.length" --datadir "$NODE1_DATADIR" 2>/dev/null | grep -oE '[0-9]+' || echo "0")
PEERS2=$(./build/bin/geth attach --exec "admin.peers.length" --datadir "$NODE2_DATADIR" 2>/dev/null | grep -oE '[0-9]+' || echo "0")

echo "   Node 1 peers: $PEERS1"
echo "   Node 2 peers: $PEERS2"

if [ "$PEERS1" = "0" ] && [ "$PEERS2" = "0" ]; then
    echo ""
    echo "⚠️  Nodes are not connected to each other!"
    echo "   Attempting to connect nodes..."
    
    # Try to get node 1 enode and connect node 2 to it
    NODE1_ENODE=$(./build/bin/geth attach --exec "admin.nodeInfo.enode" --datadir "$NODE1_DATADIR" 2>/dev/null | tr -d '"' | tr -d '\n' | grep -oE 'enode://[^?]+' || echo "")
    if [ -n "$NODE1_ENODE" ]; then
        NODE1_ENODE_CLEAN=$(echo "$NODE1_ENODE" | sed 's/?discport=0//')
        echo "   Adding Node 1 as peer to Node 2..."
        ADD_PEER=$(echo "admin.addPeer('$NODE1_ENODE_CLEAN')" | ./build/bin/geth attach --datadir "$NODE2_DATADIR" 2>/dev/null | tail -1 | grep -oE 'true|false' || echo "false")
        if echo "$ADD_PEER" | grep -q "true"; then
            echo "   ✅ Nodes connected!"
            sleep 3
            # Verify connection
            PEERS1=$(./build/bin/geth attach --exec "admin.peers.length" --datadir "$NODE1_DATADIR" 2>/dev/null | grep -oE '[0-9]+' || echo "0")
            PEERS2=$(./build/bin/geth attach --exec "admin.peers.length" --datadir "$NODE2_DATADIR" 2>/dev/null | grep -oE '[0-9]+' || echo "0")
            echo "   Node 1 peers: $PEERS1"
            echo "   Node 2 peers: $PEERS2"
        else
            echo "   ⚠️  Failed to connect nodes automatically"
            echo "   💡 Try connecting manually:"
            echo "      In Node 2 console: admin.addPeer('$NODE1_ENODE_CLEAN')"
        fi
    else
        echo "   ⚠️  Could not get Node 1 enode"
    fi
else
    echo "   ✅ Nodes are connected!"
fi

# Wait a moment and check block production
echo ""
echo "4️⃣  Checking block production..."
sleep 3

BLOCK_NUM1=$(./build/bin/geth attach --exec "eth.blockNumber" --datadir "$NODE1_DATADIR" 2>/dev/null | grep -oE '[0-9]+' || echo "0")
BLOCK_NUM2=$(./build/bin/geth attach --exec "eth.blockNumber" --datadir "$NODE2_DATADIR" 2>/dev/null | grep -oE '[0-9]+' || echo "0")

echo "   Node 1 block number: $BLOCK_NUM1"
echo "   Node 2 block number: $BLOCK_NUM2"

if [ "$BLOCK_NUM1" = "0" ] && [ "$BLOCK_NUM2" = "0" ]; then
    echo ""
    echo "⚠️  Still at block 0. Checking validator status and trying again..."
    
    # Check if validators are actually unlocked by checking coinbase
    COINBASE1=$(./build/bin/geth attach --exec "eth.coinbase" --datadir "$NODE1_DATADIR" 2>/dev/null | grep -oE '0x[a-fA-F0-9]{40}' || echo "")
    COINBASE2=$(./build/bin/geth attach --exec "eth.coinbase" --datadir "$NODE2_DATADIR" 2>/dev/null | grep -oE '0x[a-fA-F0-9]{40}' || echo "")
    
    echo "   Node 1 coinbase: $COINBASE1 (expected: $NODE1_VALIDATOR)"
    echo "   Node 2 coinbase: $COINBASE2 (expected: $NODE2_VALIDATOR)"
    
    # Try unlocking one more time if coinbase doesn't match
    if [ "$COINBASE1" != "$NODE1_VALIDATOR" ]; then
        echo "   🔄 Retrying unlock for Node 1..."
        echo "personal.unlockAccount('$NODE1_VALIDATOR', '$PASSWORD', 0)" | timeout 5 ./build/bin/geth attach --datadir "$NODE1_DATADIR" > /dev/null 2>&1
        sleep 2
    fi
    
    if [ "$COINBASE2" != "$NODE2_VALIDATOR" ]; then
        echo "   🔄 Retrying unlock for Node 2..."
        echo "personal.unlockAccount('$NODE2_VALIDATOR', '$PASSWORD', 0)" | timeout 5 ./build/bin/geth attach --datadir "$NODE2_DATADIR" > /dev/null 2>&1
        sleep 2
    fi
    
    echo ""
    echo "   Waiting 15 more seconds for blocks to start..."
    sleep 15
    
    BLOCK_NUM1=$(./build/bin/geth attach --exec "eth.blockNumber" --datadir "$NODE1_DATADIR" 2>/dev/null | grep -oE '[0-9]+' || echo "0")
    BLOCK_NUM2=$(./build/bin/geth attach --exec "eth.blockNumber" --datadir "$NODE2_DATADIR" 2>/dev/null | grep -oE '[0-9]+' || echo "0")
    
    if [ "$BLOCK_NUM1" = "0" ] && [ "$BLOCK_NUM2" = "0" ]; then
        echo ""
        echo "❌ Blocks are still not being produced!"
        echo ""
        echo "💡 Troubleshooting steps:"
        echo "   1. Make sure both nodes are running"
        echo "   2. Check that validators are in the genesis file"
        echo "   3. Verify nodes are connected: ./scripts/check-peers.sh"
        echo "   4. Try manually unlocking in geth console:"
        echo "      Terminal 1: ./build/bin/geth attach --datadir ~/local-testnet-node1"
        echo "      > personal.unlockAccount('$NODE1_VALIDATOR', '$PASSWORD', 0)"
        echo ""
        echo "      Terminal 2: ./build/bin/geth attach --datadir ~/local-testnet-node2"
        echo "      > personal.unlockAccount('$NODE2_VALIDATOR', '$PASSWORD', 0)"
        echo ""
        echo "   5. After unlocking, blocks should start within 5-10 seconds"
    else
        echo ""
        echo "✅ Blocks are now being produced! (Node 1: $BLOCK_NUM1, Node 2: $BLOCK_NUM2)"
    fi
else
    echo ""
    echo "✅ Blocks are being produced! (Node 1: $BLOCK_NUM1, Node 2: $BLOCK_NUM2)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

