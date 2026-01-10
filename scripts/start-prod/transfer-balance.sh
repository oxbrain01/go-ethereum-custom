#!/bin/bash
# Script to transfer balance between 2 wallets for testing
# Default accounts are pre-funded from genesis.json

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

# Default configuration (from start-prod.sh)
RPC_URL="http://localhost:8547"
CHAIN_ID=2026

# Default accounts (pre-funded in genesis.json)
DEFAULT_FROM="0x356981ee849c96fC40e78B0B22715345E57746fb"  # Validator account
DEFAULT_TO="0x3bE69C0DEf08196BEE31D463741Df2B92D3eaf8E"    # Second pre-funded account

# Default amount (0.1 ETH)
DEFAULT_AMOUNT_ETH="0.1"

# Parse command line arguments
FROM_ADDRESS="${1:-$DEFAULT_FROM}"
TO_ADDRESS="${2:-$DEFAULT_TO}"
AMOUNT_ETH="${3:-$DEFAULT_AMOUNT_ETH}"

# Help function
show_help() {
    echo "Transfer Balance Script for Testing"
    echo ""
    echo "Usage: $0 [FROM_ADDRESS] [TO_ADDRESS] [AMOUNT_ETH]"
    echo ""
    echo "Arguments:"
    echo "  FROM_ADDRESS  - Sender address (default: $DEFAULT_FROM)"
    echo "  TO_ADDRESS    - Recipient address (default: $DEFAULT_TO)"
    echo "  AMOUNT_ETH    - Amount to transfer in ETH (default: $DEFAULT_AMOUNT_ETH)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Transfer 0.1 ETH from default account 1 to account 2"
    echo "  $0 0x3569... 0x3bE6... 1.5           # Transfer 1.5 ETH between specific accounts"
    echo "  $0 0x3569... 0x3bE6...               # Transfer 0.1 ETH (default amount)"
    echo ""
    echo "Pre-funded accounts (from genesis.json):"
    echo "  1. 0x356981ee849c96fC40e78B0B22715345E57746fb (1,000,000 ETH)"
    echo "  2. 0x3bE69C0DEf08196BEE31D463741Df2B92D3eaf8E (1,000,000 ETH)"
    echo "  3. 0xC4fa658C3C835b316CaCB52338eD9ebbce2631D7 (1,000,000 ETH)"
    echo "  4. 0x1120CFB327baedC2f2638D75Db0935b7f3CC934b (1,000,000 ETH)"
    echo "  5. 0x554bdA38d6635155b06Faa43189B52D9eD579f70 (1,000,000 ETH)"
    exit 0
}

# Check for help flag
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    show_help
fi

# Validate addresses
if [[ ! "$FROM_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    echo "❌ Error: Invalid FROM address format: $FROM_ADDRESS"
    exit 1
fi

if [[ ! "$TO_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    echo "❌ Error: Invalid TO address format: $TO_ADDRESS"
    exit 1
fi

# Validate amount
if ! echo "$AMOUNT_ETH" | grep -qE '^[0-9]+\.?[0-9]*$'; then
    echo "❌ Error: Invalid amount: $AMOUNT_ETH (must be a number)"
    exit 1
fi

# Convert ETH to Wei
# Use Python for reliable large number handling
AMOUNT_WEI=$(python3 -c "import sys; print(int(float('$AMOUNT_ETH') * 1000000000000000000))" 2>/dev/null)
if [ -z "$AMOUNT_WEI" ] || [ "$AMOUNT_WEI" = "0" ]; then
    # Fallback to awk if Python fails
    AMOUNT_WEI=$(awk "BEGIN {printf \"%.0f\", $AMOUNT_ETH * 1000000000000000000}")
fi

# Convert to hex using Python (handles large numbers better)
AMOUNT_HEX=$(python3 -c "print(hex($AMOUNT_WEI))" 2>/dev/null)
if [ -z "$AMOUNT_HEX" ]; then
    # Fallback: ensure integer and use printf
    AMOUNT_WEI_INT=${AMOUNT_WEI%.*}
    AMOUNT_HEX=$(printf "0x%x" "$AMOUNT_WEI_INT" 2>/dev/null || echo "0x0")
fi

echo "💸 Transfer Balance Script"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "From:  $FROM_ADDRESS"
echo "To:    $TO_ADDRESS"
echo "Amount: $AMOUNT_ETH ETH ($AMOUNT_WEI Wei)"
echo "RPC:   $RPC_URL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if node is running
if ! curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    "$RPC_URL" > /dev/null 2>&1; then
    echo "❌ Error: Cannot connect to RPC endpoint: $RPC_URL"
    echo "   Make sure start-prod.sh is running!"
    exit 1
fi

# Check if we're at block 0 (genesis only)
BLOCK_NUM_HEX=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    "$RPC_URL" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

BLOCK_NUM=$(python3 -c "print(int('$BLOCK_NUM_HEX', 16))" 2>/dev/null || echo "0")

if [ "$BLOCK_NUM" -eq "0" ]; then
    echo "⚠️  Warning: Node is still at block 0 (genesis block)"
    echo "   With Clique (PoA) consensus, blocks need to be created by authorized signers."
    echo "   The node should automatically create blocks, but it may take a moment."
    echo ""
fi

# Get balances before transfer
echo "💰 Checking balances before transfer..."
FROM_BALANCE_HEX=$(curl -s -X POST -H "Content-Type: application/json" \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$FROM_ADDRESS\",\"latest\"],\"id\":1}" \
    "$RPC_URL" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

TO_BALANCE_HEX=$(curl -s -X POST -H "Content-Type: application/json" \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$TO_ADDRESS\",\"latest\"],\"id\":1}" \
    "$RPC_URL" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

# Convert hex to decimal (handle large numbers)
FROM_BALANCE=$(python3 -c "print(int('$FROM_BALANCE_HEX', 16))" 2>/dev/null || echo "0")
TO_BALANCE=$(python3 -c "print(int('$TO_BALANCE_HEX', 16))" 2>/dev/null || echo "0")

# Convert Wei to ETH for display
if command -v bc > /dev/null 2>&1; then
    FROM_BALANCE_ETH=$(echo "scale=4; $FROM_BALANCE / 1000000000000000000" | bc)
    TO_BALANCE_ETH=$(echo "scale=4; $TO_BALANCE / 1000000000000000000" | bc)
else
    FROM_BALANCE_ETH=$(awk "BEGIN {printf \"%.4f\", $FROM_BALANCE / 1000000000000000000}")
    TO_BALANCE_ETH=$(awk "BEGIN {printf \"%.4f\", $TO_BALANCE / 1000000000000000000}")
fi

echo "   From balance: $FROM_BALANCE_ETH ETH"
echo "   To balance:   $TO_BALANCE_ETH ETH"
echo ""

# Check if balances are zero (genesis not initialized)
if [ "$FROM_BALANCE" = "0" ] && [ "$TO_BALANCE" = "0" ]; then
    echo "❌ Error: Both account balances are zero!"
    echo ""
    echo "   This indicates the genesis block wasn't properly initialized."
    echo "   The pre-funded accounts should have 1,000,000 ETH each."
    echo ""
    echo "   To fix this:"
    echo "   1. Stop the node (Ctrl+C in start-prod.sh terminal)"
    echo "   2. Run: ./scripts/start-prod/fix-genesis.sh"
    echo "   3. Restart: ./scripts/start-prod/start-prod.sh"
    echo "   4. Wait a few seconds, then try this transfer again"
    echo ""
    exit 1
fi

# Check if sender has enough balance (use python for large integer comparison)
BALANCE_SUFFICIENT=$(python3 -c "print(int('$FROM_BALANCE') < int('$AMOUNT_WEI'))" 2>/dev/null || echo "True")
if [ "$BALANCE_SUFFICIENT" = "True" ]; then
    echo "❌ Error: Insufficient balance!"
    echo "   Required: $AMOUNT_ETH ETH"
    echo "   Available: $FROM_BALANCE_ETH ETH"
    exit 1
fi

# Get gas price
echo "⛽ Getting gas price..."
GAS_PRICE_HEX=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_gasPrice","params":[],"id":1}' \
    "$RPC_URL" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

GAS_PRICE=$(python3 -c "print(int('$GAS_PRICE_HEX', 16))" 2>/dev/null || echo "1000000000")
GAS_LIMIT="21000"  # Standard transfer gas limit
GAS_LIMIT_HEX=$(python3 -c "print(hex($GAS_LIMIT))" 2>/dev/null || printf "0x%x" "$GAS_LIMIT")

# Estimate gas (optional, but good practice)
echo "📊 Estimating gas..."
ESTIMATE_GAS_HEX=$(curl -s -X POST -H "Content-Type: application/json" \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_estimateGas\",\"params\":[{\"from\":\"$FROM_ADDRESS\",\"to\":\"$TO_ADDRESS\",\"value\":\"$AMOUNT_HEX\"}],\"id\":1}" \
    "$RPC_URL" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

if [ ! -z "$ESTIMATE_GAS_HEX" ] && [ "$ESTIMATE_GAS_HEX" != "null" ]; then
    ESTIMATE_GAS=$(python3 -c "print(int('$ESTIMATE_GAS_HEX', 16))" 2>/dev/null || echo "$GAS_LIMIT")
    if [ "$ESTIMATE_GAS" -gt "$GAS_LIMIT" ]; then
        GAS_LIMIT="$ESTIMATE_GAS"
        GAS_LIMIT_HEX=$(python3 -c "print(hex($GAS_LIMIT))" 2>/dev/null || printf "0x%x" "$GAS_LIMIT")
    fi
fi

# Get nonce for the transaction (use "pending" to include pending transactions)
echo "📤 Preparing transaction..."
NONCE_HEX=$(curl -s -X POST -H "Content-Type: application/json" \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getTransactionCount\",\"params\":[\"$FROM_ADDRESS\", \"pending\"],\"id\":1}" \
    "$RPC_URL" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

if [ -z "$NONCE_HEX" ]; then
    echo "❌ Failed to get nonce"
    exit 1
fi

# Sign and send transaction using Python (since --unlock is deprecated and personal API unavailable)
echo "   Amount: $AMOUNT_ETH ETH"
echo "   Gas Limit: $GAS_LIMIT"
# Display gas price in Gwei
if command -v bc > /dev/null 2>&1; then
    GAS_PRICE_GWEI=$(echo "scale=9; $GAS_PRICE / 1000000000" | bc)
else
    GAS_PRICE_GWEI=$(awk "BEGIN {printf \"%.9f\", $GAS_PRICE / 1000000000}")
fi
echo "   Gas Price: $GAS_PRICE_GWEI Gwei"
echo "   Signing transaction locally..."
echo ""

# Use Python to sign the transaction with the private key
VALIDATOR_PRIVATE_KEY="0x9de1394869030ea18ee8930c533722d71f6990b5576dee849b9c23b7d094c186"

TX_RESULT=$(python3 2>&1 <<PYTHON_SCRIPT
import json
import sys
from eth_account import Account

try:
    private_key = "$VALIDATOR_PRIVATE_KEY"
    to_addr = "$TO_ADDRESS"
    value = int("$AMOUNT_WEI")
    gas = int("$GAS_LIMIT")
    gas_price = int("$GAS_PRICE")
    nonce = int("$NONCE_HEX", 16)
    chain_id = $CHAIN_ID

    # Create transaction
    tx = {
        'nonce': nonce,
        'to': to_addr,
        'value': value,
        'gas': gas,
        'gasPrice': gas_price,
        'chainId': chain_id
    }

    # Sign transaction
    signed_tx = Account.sign_transaction(tx, private_key)
    raw_tx_hex = signed_tx.raw_transaction.hex()
    # Add 0x prefix if not present
    raw_tx = raw_tx_hex if raw_tx_hex.startswith('0x') else '0x' + raw_tx_hex

    # Send raw transaction
    import urllib.request
    import urllib.parse

    data = json.dumps({
        "jsonrpc": "2.0",
        "method": "eth_sendRawTransaction",
        "params": [raw_tx],
        "id": 1
    }).encode('utf-8')

    req = urllib.request.Request("$RPC_URL", data=data, headers={'Content-Type': 'application/json'})
    response = urllib.request.urlopen(req)
    result = json.loads(response.read().decode('utf-8'))

    if 'result' in result:
        print("SUCCESS:" + result['result'])
    elif 'error' in result:
        error_msg = result['error'].get('message', 'Unknown error')
        # "already known" means transaction was already sent - this is OK
        if 'already known' in error_msg.lower():
            # Try to extract the transaction hash from the error or use the signed tx hash
            tx_hash = signed_tx.hash.hex()
            print("SUCCESS:" + tx_hash)
        else:
            print("ERROR:" + json.dumps(result['error']))
    else:
        print("ERROR:Unknown error")
except Exception as e:
    print("ERROR:" + str(e), file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
)

# Parse the result
if echo "$TX_RESULT" | grep -q "^SUCCESS:"; then
    TX_HASH=$(echo "$TX_RESULT" | sed 's/^SUCCESS://')
elif echo "$TX_RESULT" | grep -q "^ERROR:"; then
    ERROR_MSG=$(echo "$TX_RESULT" | sed 's/^ERROR://')
    TX_HASH=""
else
    TX_HASH=""
    ERROR_MSG="Failed to sign or send transaction"
fi

# Check for errors
if [ -z "$TX_HASH" ] || [ "$TX_HASH" == "null" ]; then
    if [ ! -z "$ERROR_MSG" ]; then
        echo "❌ Transaction failed:"
        # Try to parse JSON error message
        if echo "$ERROR_MSG" | grep -q '"message"'; then
            ERROR_TEXT=$(echo "$ERROR_MSG" | python3 -c "import sys, json; print(json.load(sys.stdin).get('message', 'Unknown error'))" 2>/dev/null || echo "$ERROR_MSG")
        else
            ERROR_TEXT="$ERROR_MSG"
        fi
        echo "   $ERROR_TEXT"
    else
        echo "❌ Transaction failed: Unknown error"
        echo "   Python output: $TX_RESULT"
    fi
    
    echo ""
    echo "💡 Troubleshooting:"
    echo "   1. Check if Python eth_account is installed: pip3 install eth-account"
    echo "   2. Verify the private key is correct"
    echo "   3. Check node logs: tail -f start-prod.log"
    exit 1
fi

echo "✅ Transaction sent successfully!"
echo "   Transaction Hash: $TX_HASH"
echo ""

# Wait for transaction to be mined
echo "⏳ Waiting for transaction to be mined..."
echo "   (For Clique PoA, blocks are created automatically when transactions are pending)"
MAX_WAIT=60
for i in $(seq 1 $MAX_WAIT); do
    # Check if block number increased (block was created)
    NEW_BLOCK_HEX=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$RPC_URL" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('result', '0x0'))" 2>/dev/null || echo "0x0")
    
    NEW_BLOCK_NUM=$(python3 -c "print(int('$NEW_BLOCK_HEX', 16))" 2>/dev/null || echo "0")
    
    # Check transaction receipt
    TX_RECEIPT_JSON=$(curl -s -X POST -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getTransactionReceipt\",\"params\":[\"$TX_HASH\"],\"id\":1}" \
        "$RPC_URL")
    
    TX_RECEIPT=$(echo "$TX_RECEIPT_JSON" | python3 -c "import sys, json; d=json.load(sys.stdin); r=d.get('result'); print('SUCCESS' if r and r.get('status') == '0x1' else 'FAILED' if r and r.get('status') == '0x0' else 'WAITING')" 2>/dev/null || echo "WAITING")
    
    if [ "$TX_RECEIPT" = "SUCCESS" ]; then
        BLOCK_NUM_TX=$(echo "$TX_RECEIPT_JSON" | python3 -c "import sys, json; d=json.load(sys.stdin); r=d.get('result'); print(r.get('blockNumber', '') if r else '')" 2>/dev/null || echo "")
        echo "✅ Transaction confirmed in block $BLOCK_NUM_TX!"
        break
    elif [ "$TX_RECEIPT" = "FAILED" ]; then
        echo "❌ Transaction failed (status: 0x0)"
        exit 1
    fi
    
    if [ $i -eq $MAX_WAIT ]; then
        echo "⚠️  Transaction still pending after $MAX_WAIT seconds"
        echo "   Current block: $NEW_BLOCK_NUM"
        echo "   Transaction hash: $TX_HASH"
        echo ""
        echo "💡 If blocks aren't being created:"
        echo "   1. Check that the validator account is unlocked"
        echo "   2. Verify the validator is in the genesis extraData"
        echo "   3. Check node logs: tail -f $SCRIPT_DIR/../start-prod/start-prod.log"
        break
    fi
    
    if [ $((i % 5)) -eq 0 ]; then
        echo "   Still waiting... (block: $NEW_BLOCK_NUM, attempt: $i/$MAX_WAIT)"
    fi
    
    sleep 1
done

# Get balances after transfer
echo ""
echo "💰 Checking balances after transfer..."
FROM_BALANCE_AFTER_HEX=$(curl -s -X POST -H "Content-Type: application/json" \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$FROM_ADDRESS\",\"latest\"],\"id\":1}" \
    "$RPC_URL" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

TO_BALANCE_AFTER_HEX=$(curl -s -X POST -H "Content-Type: application/json" \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$TO_ADDRESS\",\"latest\"],\"id\":1}" \
    "$RPC_URL" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

FROM_BALANCE_AFTER=$(python3 -c "print(int('$FROM_BALANCE_AFTER_HEX', 16))" 2>/dev/null || echo "0")
TO_BALANCE_AFTER=$(python3 -c "print(int('$TO_BALANCE_AFTER_HEX', 16))" 2>/dev/null || echo "0")

# Convert Wei to ETH for display
if command -v bc > /dev/null 2>&1; then
    FROM_BALANCE_AFTER_ETH=$(echo "scale=4; $FROM_BALANCE_AFTER / 1000000000000000000" | bc)
    TO_BALANCE_AFTER_ETH=$(echo "scale=4; $TO_BALANCE_AFTER / 1000000000000000000" | bc)
else
    FROM_BALANCE_AFTER_ETH=$(awk "BEGIN {printf \"%.4f\", $FROM_BALANCE_AFTER / 1000000000000000000}")
    TO_BALANCE_AFTER_ETH=$(awk "BEGIN {printf \"%.4f\", $TO_BALANCE_AFTER / 1000000000000000000}")
fi

echo "   From balance: $FROM_BALANCE_AFTER_ETH ETH (was $FROM_BALANCE_ETH ETH)"
echo "   To balance:   $TO_BALANCE_AFTER_ETH ETH (was $TO_BALANCE_ETH ETH)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Transfer completed successfully!"
echo "   View transaction: $TX_HASH"
echo ""
