#!/bin/bash
# Script để mine một block trong dev mode

echo "⛏️  Mining a block to update chain state..."
echo ""

# Gửi transaction để trigger mining
RESULT=$(curl -s -X POST http://localhost:8546 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc":"2.0",
    "method":"eth_sendTransaction",
    "params":[{
      "from": "0x71562b71999873db5b286df957af199ec94617f7",
      "to": "0x71562b71999873db5b286df957af199ec94617f7",
      "value": "0x0"
    }],
    "id":1
  }')

echo "Transaction result: $RESULT"
echo ""
echo "Waiting for block to be mined..."
sleep 3

# Check block number
BLOCK_NUM=$(curl -s -X POST http://localhost:8546 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

if [ ! -z "$BLOCK_NUM" ]; then
  BLOCK_DEC=$(printf "%d" $BLOCK_NUM 2>/dev/null || echo "0")
  echo "✅ Block number: $BLOCK_DEC"
  if [ "$BLOCK_DEC" -gt 0 ]; then
    echo "✅ Block mined successfully! Wallet should now show balance."
  else
    echo "⚠️  Block number still 0. Try mining manually in geth console."
  fi
else
  echo "❌ Could not get block number"
fi
