#!/bin/bash
# Script to automatically create blocks when transactions are pending
# This works around the post-merge Clique block creation issue

RPC_URL="http://localhost:8546"

echo "🔄 Starting auto-mining service..."
echo "This will check for pending transactions and create blocks every 5 seconds"
echo "Press Ctrl+C to stop"
echo ""

while true; do
    # Check pending transactions
    PENDING=$(curl -s -X POST -H "Content-Type: application/json" \
      --data '{"jsonrpc":"2.0","method":"txpool_status","params":[],"id":1}' \
      "$RPC_URL" | python3 -c "import sys, json; d=json.load(sys.stdin); print(int(d['result']['pending'], 16))" 2>/dev/null || echo "0")
    
    CURRENT_BLOCK=$(curl -s -X POST -H "Content-Type: application/json" \
      --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
      "$RPC_URL" | python3 -c "import sys, json; d=json.load(sys.stdin); print(int(d['result'], 16))" 2>/dev/null || echo "0")
    
    if [ "$PENDING" -gt 0 ]; then
        echo "[$(date +%H:%M:%S)] ⏳ $PENDING pending transaction(s), block: $CURRENT_BLOCK"
        
        # Try to create a block using engine API
        HEAD_HASH=$(curl -s -X POST -H "Content-Type: application/json" \
          --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}' \
          "$RPC_URL" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['result']['hash'] if 'result' in d and d['result'] else '')" 2>/dev/null)
        
        if [ -n "$HEAD_HASH" ] && [ "$HEAD_HASH" != "None" ]; then
            TIMESTAMP=$(python3 -c "import time; print(hex(int(time.time())))")
            
            # Call ForkchoiceUpdated
            curl -s -X POST -H "Content-Type: application/json" \
              --data "{\"jsonrpc\":\"2.0\",\"method\":\"engine_forkchoiceUpdatedV1\",\"params\":[{\"headBlockHash\":\"$HEAD_HASH\",\"safeBlockHash\":\"$HEAD_HASH\",\"finalizedBlockHash\":\"$HEAD_HASH\"},{\"timestamp\":$TIMESTAMP,\"prevRandao\":\"0x0000000000000000000000000000000000000000000000000000000000000000\",\"suggestedFeeRecipient\":\"0x356981ee849c96fC40e78B0B22715345E57746fb\"}],\"id\":1}" \
              "$RPC_URL" > /dev/null 2>&1
        fi
    else
        if [ "$(($(date +%s) % 10))" -eq 0 ]; then
            echo "[$(date +%H:%M:%S)] ✅ No pending transactions, block: $CURRENT_BLOCK"
        fi
    fi
    
    sleep 5
done

