#!/bin/bash
# Script to start mining on the blockchain
# This is needed for Clique (PoA) consensus to create blocks

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

RPC_URL="http://localhost:8547"

echo "⛏️  Starting Mining"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if node is running
if ! curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    "$RPC_URL" > /dev/null 2>&1; then
    echo "❌ Error: Cannot connect to RPC endpoint: $RPC_URL"
    echo "   Make sure start-prod.sh is running!"
    exit 1
fi

# Check current mining status
MINING=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_mining","params":[],"id":1}' \
    "$RPC_URL" | grep -o '"result":[^,}]*' | cut -d':' -f2 | tr -d ' ')

if [ "$MINING" == "true" ]; then
    echo "✅ Mining is already active"
    exit 0
fi

# Start mining
echo "📤 Starting miner..."
RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"miner_start","params":[1],"id":1}' \
    "$RPC_URL")

# Check for errors in the response
ERROR=$(echo "$RESPONSE" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('error', {}).get('message', '') if 'error' in d else '')" 2>/dev/null || echo "")

if [ -n "$ERROR" ]; then
    echo "❌ Failed to start mining"
    echo "   Error: $ERROR"
    echo ""
    echo "💡 Note: For Clique (PoA), blocks are created automatically by authorized signers."
    echo "   Make sure the validator account is unlocked and authorized in genesis."
    exit 1
fi

# Extract result and normalize to lowercase string
RESULT=$(echo "$RESPONSE" | python3 -c "import sys, json; d=json.load(sys.stdin); r=d.get('result'); print('true' if r is True else 'false' if r is False else 'null' if r is None else str(r).lower())" 2>/dev/null || echo "")

if [ "$RESULT" == "true" ] || [ "$RESULT" == "null" ]; then
    echo "✅ Mining started successfully!"
    echo ""
    echo "💡 Note: For Clique (PoA), blocks are created automatically."
    echo "   Your node will create blocks if it's an authorized signer."
    echo ""
    echo "⏳ Waiting for first block..."
    sleep 3
    
    # Check block number
    BLOCK_NUM_HEX=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$RPC_URL" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('result', '0x0'))" 2>/dev/null || echo "0x0")
    
    BLOCK_NUM=$(python3 -c "print(int('$BLOCK_NUM_HEX', 16))" 2>/dev/null || echo "0")
    echo "   Current block: $BLOCK_NUM"
    
    if [ "$BLOCK_NUM" -gt "0" ]; then
        echo "✅ Blocks are being created!"
    else
        echo "⚠️  Still at block 0. Blocks will be created automatically by authorized signers."
    fi
else
    echo "❌ Failed to start mining"
    if [ "$RESULT" == "false" ]; then
        echo "   Miner returned false"
    else
        echo "   Unexpected response: $RESULT"
    fi
    echo "   Full response: $RESPONSE"
    exit 1
fi
