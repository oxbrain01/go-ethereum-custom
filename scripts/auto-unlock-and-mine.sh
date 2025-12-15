#!/bin/bash
# Script để tự động unlock validators và đảm bảo blocks được tạo

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

NODE1_DATADIR="${HOME}/local-testnet-node1"
NODE2_DATADIR="${HOME}/local-testnet-node2"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔓 AUTO UNLOCK VALIDATORS & START MINING"
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

echo "1️⃣  Connecting nodes..."
./scripts/force-connect-v2.sh > /dev/null 2>&1
sleep 3

echo ""
echo "2️⃣  Unlocking Node 1 validator..."
UNLOCK1=$(echo "personal.unlockAccount('$NODE1_VALIDATOR', '$PASSWORD', 0)" | ./build/bin/geth attach --datadir "$NODE1_DATADIR" 2>/dev/null | tail -1 | grep -oE "true|false|Error" || echo "unknown")
if echo "$UNLOCK1" | grep -q "true"; then
    echo "   ✅ Node 1 validator unlocked"
else
    echo "   ⚠️  Node 1 unlock: $UNLOCK1"
    echo "   💡 Try manually: ./build/bin/geth attach --datadir ~/local-testnet-node1"
    echo "      Then run: personal.unlockAccount('$NODE1_VALIDATOR', '$PASSWORD', 0)"
fi

echo ""
echo "3️⃣  Unlocking Node 2 validator..."
UNLOCK2=$(echo "personal.unlockAccount('$NODE2_VALIDATOR', '$PASSWORD', 0)" | ./build/bin/geth attach --datadir "$NODE2_DATADIR" 2>/dev/null | tail -1 | grep -oE "true|false|Error" || echo "unknown")
if echo "$UNLOCK2" | grep -q "true"; then
    echo "   ✅ Node 2 validator unlocked"
else
    echo "   ⚠️  Node 2 unlock: $UNLOCK2"
    echo "   💡 Try manually: ./build/bin/geth attach --datadir ~/local-testnet-node2"
    echo "      Then run: personal.unlockAccount('$NODE2_VALIDATOR', '$PASSWORD', 0)"
fi

echo ""
echo "4️⃣  Waiting for blocks to be created (15 seconds)..."
sleep 15

echo ""
echo "5️⃣  Checking status..."
BLOCK_NUM=$(./build/bin/geth attach --exec "eth.blockNumber" --datadir "$NODE1_DATADIR" 2>/dev/null | tr -d '\n' | grep -oE '[0-9]+' || echo "0")
PEERS=$(./build/bin/geth attach --exec "admin.peers.length" --datadir "$NODE1_DATADIR" 2>/dev/null | tr -d '\n' | grep -oE '[0-9]+' || echo "0")

echo "   Block number: $BLOCK_NUM"
echo "   Peers: $PEERS"

if [ "$BLOCK_NUM" = "0" ]; then
    echo ""
    echo "⚠️  Still no blocks created!"
    echo ""
    echo "💡 Manual unlock required:"
    echo ""
    echo "   Terminal 1:"
    echo "   ./build/bin/geth attach --datadir ~/local-testnet-node1"
    echo "   > personal.unlockAccount('$NODE1_VALIDATOR', '$PASSWORD', 0)"
    echo ""
    echo "   Terminal 2:"
    echo "   ./build/bin/geth attach --datadir ~/local-testnet-node2"
    echo "   > personal.unlockAccount('$NODE2_VALIDATOR', '$PASSWORD', 0)"
else
    echo ""
    echo "✅ Blocks are being created! Transactions will be confirmed."
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

