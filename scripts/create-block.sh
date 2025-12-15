#!/bin/bash
# Script to manually create a block using Engine API
# This is needed for post-merge Clique consensus

RPC_URL="http://localhost:8546"

echo "🔨 Creating block to mine pending transactions..."

# Get current head block
HEAD_BLOCK=$(curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}' \
  "$RPC_URL" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['result']['hash'] if 'result' in d and d['result'] else '')")

if [ -z "$HEAD_BLOCK" ] || [ "$HEAD_BLOCK" = "None" ]; then
    echo "❌ Could not get head block"
    exit 1
fi

echo "Current head: $HEAD_BLOCK"

# Get current timestamp
TIMESTAMP=$(python3 -c "import time; print(hex(int(time.time())))")

# Use ForkchoiceUpdated to create a new block
# For Clique, we need to provide payload attributes
RESULT=$(curl -s -X POST -H "Content-Type: application/json" \
  --data "{
    \"jsonrpc\":\"2.0\",
    \"method\":\"engine_forkchoiceUpdatedV1\",
    \"params\":[{
      \"headBlockHash\":\"$HEAD_BLOCK\",
      \"safeBlockHash\":\"$HEAD_BLOCK\",
      \"finalizedBlockHash\":\"$HEAD_BLOCK\"
    },{
      \"timestamp\":$TIMESTAMP,
      \"prevRandao\":\"0x0000000000000000000000000000000000000000000000000000000000000000\",
      \"suggestedFeeRecipient\":\"0x356981ee849c96fC40e78B0B22715345E57746fb\"
    }],
    \"id\":1
  }" \
  "$RPC_URL")

echo "ForkchoiceUpdated result: $RESULT"

# Check if we got a payload ID
PAYLOAD_ID=$(echo "$RESULT" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['result']['payloadId'] if 'result' in d and 'payloadId' in d['result'] else '')" 2>/dev/null)

if [ -n "$PAYLOAD_ID" ] && [ "$PAYLOAD_ID" != "None" ]; then
    echo "✅ Got payload ID: $PAYLOAD_ID"
    
    # Get the payload
    sleep 1
    PAYLOAD=$(curl -s -X POST -H "Content-Type: application/json" \
      --data "{\"jsonrpc\":\"2.0\",\"method\":\"engine_getPayloadV1\",\"params\":[\"$PAYLOAD_ID\"],\"id\":1}" \
      "$RPC_URL")
    
    echo "Payload: $PAYLOAD"
    
    # Execute the payload
    EXEC_RESULT=$(curl -s -X POST -H "Content-Type: application/json" \
      --data "{\"jsonrpc\":\"2.0\",\"method\":\"engine_newPayloadV1\",\"params\":[$PAYLOAD],\"id\":1}" \
      "$RPC_URL")
    
    echo "Execution result: $EXEC_RESULT"
else
    echo "⚠️  No payload ID returned. Block may be created automatically or there's an issue."
fi

# Check new block number
sleep 2
NEW_BLOCK=$(curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  "$RPC_URL" | python3 -c "import sys, json; d=json.load(sys.stdin); print(int(d['result'], 16))")

echo "New block number: $NEW_BLOCK"

