#!/bin/bash
# Script to ensure validators are unlocked and blocks are being produced
# Run this after starting both nodes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

NODE1_DATADIR="${HOME}/local-testnet-node1"
NODE2_DATADIR="${HOME}/local-testnet-node2"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 ENSURING BLOCKS ARE BEING PRODUCED"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# First, run the unlock script
echo "Step 1: Unlocking validators..."
./scripts/unlock-validators.sh

echo ""
echo "Step 2: Final verification..."
sleep 5

BLOCK_NUM1=$(./build/bin/geth attach --exec "eth.blockNumber" --datadir "$NODE1_DATADIR" 2>/dev/null | grep -oE '[0-9]+' || echo "0")
BLOCK_NUM2=$(./build/bin/geth attach --exec "eth.blockNumber" --datadir "$NODE2_DATADIR" 2>/dev/null | grep -oE '[0-9]+' || echo "0")
PEERS1=$(./build/bin/geth attach --exec "admin.peers.length" --datadir "$NODE1_DATADIR" 2>/dev/null | grep -oE '[0-9]+' || echo "0")
PEERS2=$(./build/bin/geth attach --exec "admin.peers.length" --datadir "$NODE2_DATADIR" 2>/dev/null | grep -oE '[0-9]+' || echo "0")

echo "   Block numbers: Node 1=$BLOCK_NUM1, Node 2=$BLOCK_NUM2"
echo "   Peer counts: Node 1=$PEERS1, Node 2=$PEERS2"

if [ "$BLOCK_NUM1" = "0" ] && [ "$BLOCK_NUM2" = "0" ]; then
    echo ""
    echo "❌ Blocks are still not being produced!"
    echo ""
    echo "🔍 Diagnostic information:"
    
    # Check coinbase
    COINBASE1=$(./build/bin/geth attach --exec "eth.coinbase" --datadir "$NODE1_DATADIR" 2>/dev/null | grep -oE '0x[a-fA-F0-9]{40}' || echo "unknown")
    COINBASE2=$(./build/bin/geth attach --exec "eth.coinbase" --datadir "$NODE2_DATADIR" 2>/dev/null | grep -oE '0x[a-fA-F0-9]{40}' || echo "unknown")
    NODE1_VALIDATOR=$(cat "${NODE1_DATADIR}/validator_address.txt" 2>/dev/null | tr -d '\n')
    NODE2_VALIDATOR=$(cat "${NODE2_DATADIR}/validator_address.txt" 2>/dev/null | tr -d '\n')
    
    echo "   Node 1 coinbase: $COINBASE1"
    echo "   Node 1 validator: $NODE1_VALIDATOR"
    echo "   Node 2 coinbase: $COINBASE2"
    echo "   Node 2 validator: $NODE2_VALIDATOR"
    
    if [ "$COINBASE1" != "$NODE1_VALIDATOR" ] || [ "$COINBASE2" != "$NODE2_VALIDATOR" ]; then
        echo ""
        echo "⚠️  Validators are not set as coinbase!"
        echo "   This means they are not unlocked for signing blocks."
        echo ""
        echo "💡 Manual fix required:"
        echo "   Open two terminals and run these commands:"
        echo ""
        echo "   Terminal 1:"
        echo "   ./build/bin/geth attach --datadir ~/local-testnet-node1"
        echo "   > personal.unlockAccount('$NODE1_VALIDATOR', 'validator123', 0)"
        echo ""
        echo "   Terminal 2:"
        echo "   ./build/bin/geth attach --datadir ~/local-testnet-node2"
        echo "   > personal.unlockAccount('$NODE2_VALIDATOR', 'validator123', 0)"
        echo ""
        echo "   After unlocking, blocks should start within 5-10 seconds."
    fi
    
    if [ "$PEERS1" = "0" ] && [ "$PEERS2" = "0" ]; then
        echo ""
        echo "⚠️  Nodes are not connected to each other!"
        echo "   Run: ./scripts/check-peers.sh"
    fi
else
    echo ""
    echo "✅ SUCCESS! Blocks are being produced!"
    echo "   You can now send transactions and they will be mined."
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

