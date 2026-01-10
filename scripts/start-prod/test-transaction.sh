#!/bin/bash
# Script to test and make a successful transaction
# This script will send a transaction and ensure it gets mined

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

# Configuration
RPC_URL="http://localhost:8547"
CHAIN_ID=2026
FROM_ADDRESS="0x356981ee849c96fC40e78B0B22715345E57746fb"
TO_ADDRESS="0x3bE69C0DEf08196BEE31D463741Df2B92D3eaf8E"
VALIDATOR_PRIVATE_KEY="0x9de1394869030ea18ee8930c533722d71f6990b5576dee849b9c23b7d094c186"
AMOUNT_ETH="${1:-0.1}"

echo "🧪 Transaction Test Script"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "From:  $FROM_ADDRESS"
echo "To:    $TO_ADDRESS"
echo "Amount: $AMOUNT_ETH ETH"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if node is running
echo "🔍 Checking node status..."
if ! curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    "$RPC_URL" > /dev/null 2>&1; then
    echo "❌ Error: Cannot connect to RPC endpoint: $RPC_URL"
    echo "   Make sure start-prod.sh is running!"
    exit 1
fi

# Get current block number
BLOCK_NUM_HEX=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    "$RPC_URL" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('result', '0x0'))" 2>/dev/null || echo "0x0")

BLOCK_NUM=$(python3 -c "print(int('$BLOCK_NUM_HEX', 16))" 2>/dev/null || echo "0")
echo "   Current block: $BLOCK_NUM"

# Get balances - try both "latest" and "0x0" (genesis block)
echo "💰 Checking balances..."
FROM_BALANCE_HEX=$(curl -s -X POST -H "Content-Type: application/json" \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$FROM_ADDRESS\",\"latest\"],\"id\":1}" \
    "$RPC_URL" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('result', '0x0'))" 2>/dev/null || echo "0x0")

# If balance is zero at latest, try genesis block
FROM_BALANCE=$(python3 -c "print(int('$FROM_BALANCE_HEX', 16))" 2>/dev/null || echo "0")
if [ "$FROM_BALANCE" = "0" ]; then
    echo "   Trying genesis block (0x0)..."
    FROM_BALANCE_HEX=$(curl -s -X POST -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$FROM_ADDRESS\",\"0x0\"],\"id\":1}" \
        "$RPC_URL" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('result', '0x0'))" 2>/dev/null || echo "0x0")
    FROM_BALANCE=$(python3 -c "print(int('$FROM_BALANCE_HEX', 16))" 2>/dev/null || echo "0")
fi

FROM_BALANCE_ETH=$(python3 -c "print($FROM_BALANCE / 1000000000000000000)" 2>/dev/null || echo "0")
echo "   From balance: $FROM_BALANCE_ETH ETH"

# Check if balance is zero and provide helpful error
if [ "$FROM_BALANCE" = "0" ] || [ -z "$FROM_BALANCE" ]; then
    echo ""
    echo "⚠️  Warning: Account balance is zero!"
    echo "   This usually means the genesis block wasn't properly initialized."
    echo ""
    echo "   The genesis block exists (block 0), but balances aren't accessible."
    echo "   This might be fixed by creating the first block (block 1)."
    echo ""
    echo "   🔧 Quick fix (try this first):"
    echo "      ./scripts/start-prod/force-create-block1.sh"
    echo ""
    echo "   🔧 Full fix (if quick fix doesn't work):"
    echo "      1. Stop the node (Ctrl+C in start-prod.sh terminal)"
    echo "      2. Run: ./scripts/start-prod/fix-genesis-balances.sh"
    echo "      3. Restart the node: ./scripts/start-prod/start-prod.sh"
    echo "      4. Wait for auto-mine.sh to create block 1"
    echo ""
    exit 1
fi

# Convert amount to Wei
AMOUNT_WEI=$(python3 -c "print(int(float('$AMOUNT_ETH') * 1000000000000000000))" 2>/dev/null)
AMOUNT_HEX=$(python3 -c "print(hex($AMOUNT_WEI))" 2>/dev/null)

# Get gas price
echo "⛽ Getting gas price..."
GAS_PRICE_HEX=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_gasPrice","params":[],"id":1}' \
    "$RPC_URL" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('result', '0x3b9aca00'))" 2>/dev/null || echo "0x3b9aca00")

GAS_PRICE=$(python3 -c "print(int('$GAS_PRICE_HEX', 16))" 2>/dev/null || echo "1000000000")
GAS_LIMIT=21000
GAS_LIMIT_HEX=$(python3 -c "print(hex($GAS_LIMIT))" 2>/dev/null)

# Get nonce (use "pending" to include pending transactions)
echo "📤 Getting nonce..."
NONCE_HEX=$(curl -s -X POST -H "Content-Type: application/json" \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getTransactionCount\",\"params\":[\"$FROM_ADDRESS\",\"pending\"],\"id\":1}" \
    "$RPC_URL" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('result', '0x0'))" 2>/dev/null || echo "0x0")

NONCE=$(python3 -c "print(int('$NONCE_HEX', 16))" 2>/dev/null || echo "0")
echo "   Nonce: $NONCE (includes pending transactions)"

# Sign and send transaction
echo ""
echo "📝 Signing and sending transaction..."
echo "   Amount: $AMOUNT_ETH ETH"
echo "   Gas: $GAS_LIMIT"
echo "   Gas Price: $(python3 -c "print($GAS_PRICE / 1000000000)") Gwei"
echo ""

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
    nonce = int("$NONCE")
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
        if 'already known' in error_msg.lower():
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

# Parse result
if echo "$TX_RESULT" | grep -q "^SUCCESS:"; then
    TX_HASH=$(echo "$TX_RESULT" | sed 's/^SUCCESS://')
    echo "✅ Transaction sent successfully!"
    echo "   Transaction Hash: $TX_HASH"
else
    ERROR_MSG=$(echo "$TX_RESULT" | sed 's/^ERROR://')
    echo "❌ Transaction failed:"
    if echo "$ERROR_MSG" | grep -q '"message"'; then
        ERROR_TEXT=$(echo "$ERROR_MSG" | python3 -c "import sys, json; print(json.load(sys.stdin).get('message', 'Unknown error'))" 2>/dev/null || echo "$ERROR_MSG")
    else
        ERROR_TEXT="$ERROR_MSG"
    fi
    echo "   $ERROR_TEXT"
    exit 1
fi

echo ""
echo "⏳ Waiting for transaction to be mined..."
echo "   (For Clique PoA, blocks are created when transactions are pending)"

# Wait for transaction receipt
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
    
    TX_RECEIPT=$(echo "$TX_RECEIPT_JSON" | python3 -c "import sys, json; d=json.load(sys.stdin); r=d.get('result'); print('SUCCESS' if r and r.get('status') == '0x1' else 'PENDING' if r and r.get('status') == '0x0' else 'WAITING')" 2>/dev/null || echo "WAITING")
    
    if [ "$TX_RECEIPT" = "SUCCESS" ]; then
        BLOCK_HASH=$(echo "$TX_RECEIPT_JSON" | python3 -c "import sys, json; d=json.load(sys.stdin); r=d.get('result'); print(r.get('blockHash', '') if r else '')" 2>/dev/null || echo "")
        BLOCK_NUM_TX=$(echo "$TX_RECEIPT_JSON" | python3 -c "import sys, json; d=json.load(sys.stdin); r=d.get('result'); print(r.get('blockNumber', '') if r else '')" 2>/dev/null || echo "")
        echo "✅ Transaction confirmed in block $BLOCK_NUM_TX!"
        break
    elif [ "$TX_RECEIPT" = "PENDING" ]; then
        echo "❌ Transaction failed (status: 0x0)"
        exit 1
    fi
    
    if [ $i -eq $MAX_WAIT ]; then
        echo "⚠️  Transaction still pending after $MAX_WAIT seconds"
        echo "   This might mean blocks aren't being created automatically"
        echo "   Try running: ./scripts/start-prod/start-mining.sh"
        break
    fi
    
    if [ $((i % 5)) -eq 0 ]; then
        echo "   Still waiting... (block: $NEW_BLOCK_NUM, attempt: $i/$MAX_WAIT)"
    fi
    
    sleep 1
done

# Get final balances
echo ""
echo "💰 Final balances:"
FROM_BALANCE_FINAL_HEX=$(curl -s -X POST -H "Content-Type: application/json" \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$FROM_ADDRESS\",\"latest\"],\"id\":1}" \
    "$RPC_URL" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('result', '0x0'))" 2>/dev/null || echo "0x0")

TO_BALANCE_FINAL_HEX=$(curl -s -X POST -H "Content-Type: application/json" \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$TO_ADDRESS\",\"latest\"],\"id\":1}" \
    "$RPC_URL" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('result', '0x0'))" 2>/dev/null || echo "0x0")

FROM_BALANCE_FINAL=$(python3 -c "print(int('$FROM_BALANCE_FINAL_HEX', 16))" 2>/dev/null || echo "0")
TO_BALANCE_FINAL=$(python3 -c "print(int('$TO_BALANCE_FINAL_HEX', 16))" 2>/dev/null || echo "0")

FROM_BALANCE_FINAL_ETH=$(python3 -c "print($FROM_BALANCE_FINAL / 1000000000000000000)" 2>/dev/null || echo "0")
TO_BALANCE_FINAL_ETH=$(python3 -c "print($TO_BALANCE_FINAL / 1000000000000000000)" 2>/dev/null || echo "0")

echo "   From: $FROM_BALANCE_FINAL_ETH ETH"
echo "   To:   $TO_BALANCE_FINAL_ETH ETH"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Transaction test completed!"
echo "   TX Hash: $TX_HASH"
echo ""
