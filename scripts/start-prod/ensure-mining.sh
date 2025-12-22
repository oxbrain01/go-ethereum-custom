# #!/bin/bash
# # Script to ensure mining is enabled after node starts

# sleep 5  # Wait for node to be ready

# echo "🔍 Checking mining status..."

# # Check if node is running
# BLOCK_NUM=$(curl -s -X POST -H "Content-Type: application/json" \
#   --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
#   http://localhost:8545 2>/dev/null | grep -oE '"result":"0x[0-9a-f]+"' | cut -d'"' -f4)

# if [ -z "$BLOCK_NUM" ]; then
#     echo "❌ Node is not responding"
#     exit 1
# fi

# # Note: Account is already unlocked via --unlock flag when starting geth
# echo "🔓 Validator account should be unlocked via --unlock flag"

# # Set coinbase
# echo "💰 Setting coinbase..."
# COINBASE_RESULT=$(curl -s -X POST -H "Content-Type: application/json" \
#   --data '{"jsonrpc":"2.0","method":"miner_setEtherbase","params":["0x356981ee849c96fC40e78B0B22715345E57746fb"],"id":1}' \
#   http://localhost:8545 2>/dev/null)

# if echo "$COINBASE_RESULT" | grep -q "true"; then
#     echo "✅ Coinbase set"
# else
#     echo "⚠️  Could not set coinbase: $COINBASE_RESULT"
# fi

# # Start mining (if available)
# echo "⛏️  Starting mining..."
# MINER_START=$(curl -s -X POST -H "Content-Type: application/json" \
#   --data '{"jsonrpc":"2.0","method":"miner_start","params":[1],"id":1}' \
#   http://localhost:8545 2>/dev/null)

# if echo "$MINER_START" | grep -q "true\|null"; then
#     echo "✅ Mining started"
# else
#     echo "⚠️  Mining API response: $MINER_START"
#     echo "   (This is normal for Clique - blocks are created automatically)"
# fi

# echo ""
# echo "✅ Setup complete. Blocks should be created every 5 seconds."

