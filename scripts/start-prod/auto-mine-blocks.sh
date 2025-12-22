# #!/bin/bash
# # Script to automatically create blocks via Engine API for Clique consensus
# # This simulates what SimulatedBeacon does

# set -e

# RPC_URL="http://localhost:8545"
# ENGINE_URL="http://localhost:8551"
# FEE_RECIPIENT="0x356981ee849c96fC40e78B0B22715345E57746fb"
# PERIOD=5  # Block period in seconds

# echo "⛏️  Starting automatic block creation..."
# echo "   Period: $PERIOD seconds"
# echo "   Fee Recipient: $FEE_RECIPIENT"
# echo ""

# # Wait for node to be ready
# echo "⏳ Waiting for node to be ready..."
# for i in {1..30}; do
#     if curl -s -X POST -H "Content-Type: application/json" \
#         --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
#         "$RPC_URL" > /dev/null 2>&1; then
#         echo "✅ Node is ready"
#         break
#     fi
#     if [ $i -eq 30 ]; then
#         echo "❌ Node is not responding after 30 attempts"
#         exit 1
#     fi
#     sleep 1
# done

# # Get current block
# get_current_block() {
#     curl -s -X POST -H "Content-Type: application/json" \
#         --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest", false],"id":1}' \
#         "$RPC_URL" | grep -oE '"hash":"0x[0-9a-f]+"' | head -1 | cut -d'"' -f4
# }

# # Create new block via Engine API
# create_block() {
#     local head_hash=$1
#     local timestamp=$(printf "0x%x" $(date +%s))
    
#     # ForkchoiceUpdated
#     local fc_result=$(curl -s -X POST -H "Content-Type: application/json" \
#         --data "{
#             \"jsonrpc\":\"2.0\",
#             \"method\":\"engine_forkchoiceUpdatedV2\",
#             \"params\":[{
#                 \"headBlockHash\":\"$head_hash\",
#                 \"safeBlockHash\":\"$head_hash\",
#                 \"finalizedBlockHash\":\"$head_hash\"
#             },{
#                 \"timestamp\":$timestamp,
#                 \"suggestedFeeRecipient\":\"$FEE_RECIPIENT\",
#                 \"random\":\"0x0000000000000000000000000000000000000000000000000000000000000000\"
#             }],
#             \"id\":1
#         }" "$ENGINE_URL")
    
#     local payload_id=$(echo "$fc_result" | grep -oE '"payloadId":"0x[0-9a-f]+"' | cut -d'"' -f4)
    
#     if [ -z "$payload_id" ]; then
#         echo "⚠️  No payload ID returned"
#         return 1
#     fi
    
#     # GetPayload
#     sleep 1  # Wait a bit for payload to be ready
#     local payload_result=$(curl -s -X POST -H "Content-Type: application/json" \
#         --data "{
#             \"jsonrpc\":\"2.0\",
#             \"method\":\"engine_getPayloadV2\",
#             \"params\":[\"$payload_id\"],
#             \"id\":1
#         }" "$ENGINE_URL")
    
#     local block_hash=$(echo "$payload_result" | grep -oE '"blockHash":"0x[0-9a-f]+"' | head -1 | cut -d'"' -f4)
    
#     if [ ! -z "$block_hash" ]; then
#         # NewPayload
#         curl -s -X POST -H "Content-Type: application/json" \
#             --data "{
#                 \"jsonrpc\":\"2.0\",
#                 \"method\":\"engine_newPayloadV2\",
#                 \"params\":[$(echo "$payload_result" | grep -oE '"params":\[.*\]' | cut -d'[' -f2 | cut -d']' -f1)],
#                 \"id\":1
#             }" "$ENGINE_URL" > /dev/null
        
#         # ForkchoiceUpdated again to set new head
#         curl -s -X POST -H "Content-Type: application/json" \
#             --data "{
#                 \"jsonrpc\":\"2.0\",
#                 \"method\":\"engine_forkchoiceUpdatedV2\",
#                 \"params\":[{
#                     \"headBlockHash\":\"$block_hash\",
#                     \"safeBlockHash\":\"$block_hash\",
#                     \"finalizedBlockHash\":\"$block_hash\"
#                 }],
#                 \"id\":1
#             }" "$ENGINE_URL" > /dev/null
        
#         echo "✅ Created block: $block_hash"
#         return 0
#     fi
    
#     return 1
# }

# # Main loop
# echo "🔄 Starting block creation loop..."
# while true; do
#     CURRENT_BLOCK=$(get_current_block)
#     if [ ! -z "$CURRENT_BLOCK" ]; then
#         create_block "$CURRENT_BLOCK"
#     else
#         echo "⚠️  Could not get current block"
#     fi
#     sleep "$PERIOD"
# done

