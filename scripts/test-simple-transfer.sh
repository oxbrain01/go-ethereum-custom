#!/bin/bash
# Simple script to test ETH transfer on local blockchain

set -e

RPC_URL="http://localhost:8546"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ACCOUNTS_FILE="$SCRIPT_DIR/test-accounts.json"

echo "🧪 Testing ETH Transfer on Local Blockchain"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if node is running
echo "🔍 Checking if node is running..."
if ! curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  "$RPC_URL" > /dev/null 2>&1; then
    echo "❌ Node is not running or not accessible at $RPC_URL"
    echo "💡 Please start the node first: ./scripts/start-local-blockchain.sh"
    exit 1
fi
echo "✅ Node is running"
echo ""

# Check if test accounts file exists
if [ ! -f "$TEST_ACCOUNTS_FILE" ]; then
    echo "❌ Test accounts file not found: $TEST_ACCOUNTS_FILE"
    exit 1
fi

# Read accounts from JSON
FROM_ADDRESS=$(cat "$TEST_ACCOUNTS_FILE" | grep -A 4 '"address":' | head -5 | grep '"address":' | head -1 | cut -d'"' -f4)
TO_ADDRESS=$(cat "$TEST_ACCOUNTS_FILE" | grep -A 4 '"address":' | head -10 | grep '"address":' | tail -1 | cut -d'"' -f4)
FROM_PRIVATE_KEY=$(cat "$TEST_ACCOUNTS_FILE" | grep -A 4 '"privateKey":' | head -5 | grep '"privateKey":' | head -1 | cut -d'"' -f4)

if [ -z "$FROM_ADDRESS" ] || [ -z "$TO_ADDRESS" ] || [ -z "$FROM_PRIVATE_KEY" ]; then
    echo "❌ Failed to read accounts from test-accounts.json"
    exit 1
fi

echo "📋 Transaction Details:"
echo "   From: $FROM_ADDRESS"
echo "   To:   $TO_ADDRESS"
echo "   Amount: 0.1 ETH"
echo ""

# Check balances before
echo "💰 Checking balances before transfer..."
FROM_BALANCE_HEX=$(curl -s -X POST -H "Content-Type: application/json" \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$FROM_ADDRESS\",\"latest\"],\"id\":1}" \
  "$RPC_URL" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

TO_BALANCE_HEX=$(curl -s -X POST -H "Content-Type: application/json" \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$TO_ADDRESS\",\"latest\"],\"id\":1}" \
  "$RPC_URL" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

FROM_BALANCE=$(printf "%d" $FROM_BALANCE_HEX 2>/dev/null || echo "0")
TO_BALANCE=$(printf "%d" $TO_BALANCE_HEX 2>/dev/null || echo "0")

FROM_BALANCE_ETH=$(echo "scale=4; $FROM_BALANCE / 1000000000000000000" | bc)
TO_BALANCE_ETH=$(echo "scale=4; $TO_BALANCE / 1000000000000000000" | bc)

echo "   From balance: $FROM_BALANCE_ETH ETH"
echo "   To balance:   $TO_BALANCE_ETH ETH"
echo ""

# Get nonce
echo "📝 Getting transaction nonce..."
NONCE_HEX=$(curl -s -X POST -H "Content-Type: application/json" \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getTransactionCount\",\"params\":[\"$FROM_ADDRESS\",\"latest\"],\"id\":1}" \
  "$RPC_URL" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

# Get gas price
GAS_PRICE_HEX=$(curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_gasPrice","params":[],"id":1}' \
  "$RPC_URL" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

# Prepare transaction
AMOUNT_WEI="0x16345785D8A0000"  # 0.1 ETH in hex
GAS_LIMIT="0x5208"  # 21000

echo "📤 Sending transaction..."
echo "   Nonce: $NONCE_HEX"
echo "   Amount: 0.1 ETH"
echo ""

# Use Python to sign and send transaction
python3 << EOF
import json
import requests
from eth_account import Account

# Enable unaudited HD wallet features
Account.enable_unaudited_hdwallet_features()

rpc_url = "$RPC_URL"
from_address = "$FROM_ADDRESS"
to_address = "$TO_ADDRESS"
private_key = "$FROM_PRIVATE_KEY"
nonce_hex = "$NONCE_HEX"
gas_price_hex = "$GAS_PRICE_HEX"
amount_wei = "$AMOUNT_WEI"
gas_limit = "$GAS_LIMIT"
chain_id = 1337

# Create transaction
transaction = {
    'nonce': int(nonce_hex, 16),
    'to': to_address,
    'value': int(amount_wei, 16),
    'gas': int(gas_limit, 16),
    'gasPrice': int(gas_price_hex, 16),
    'chainId': chain_id
}

# Sign transaction
signed_txn = Account.sign_transaction(transaction, private_key)

# Send transaction
tx_hash = signed_txn.hash.hex()
# Get raw transaction (newer eth-account uses raw_transaction)
raw_tx = getattr(signed_txn, 'raw_transaction', getattr(signed_txn, 'rawTransaction', None))
tx_hex = '0x' + raw_tx.hex()

payload = {
    "jsonrpc": "2.0",
    "method": "eth_sendRawTransaction",
    "params": [tx_hex],
    "id": 1
}

response = requests.post(rpc_url, json=payload)
result = response.json()

if 'error' in result:
    print(f"❌ Error: {result['error']}")
    exit(1)
else:
    print(f"✅ Transaction sent!")
    print(f"   Transaction Hash: {result['result']}")
    print(f"")
    print(f"⏳ Waiting for transaction to be mined...")
    
    # Wait for transaction receipt
    import time
    max_wait = 30
    waited = 0
    while waited < max_wait:
        time.sleep(1)
        waited += 1
        
        receipt_payload = {
            "jsonrpc": "2.0",
            "method": "eth_getTransactionReceipt",
            "params": [result['result']],
            "id": 1
        }
        
        receipt_response = requests.post(rpc_url, json=receipt_payload)
        receipt_result = receipt_response.json()
        
        if 'result' in receipt_result and receipt_result['result'] is not None:
            receipt = receipt_result['result']
            status = receipt.get('status', '0x0')
            if status == '0x1':
                print(f"✅ Transaction confirmed!")
                print(f"   Block Number: {int(receipt['blockNumber'], 16)}")
                print(f"   Gas Used: {int(receipt['gasUsed'], 16)}")
                break
            else:
                print(f"❌ Transaction failed")
                break
        
        if waited % 5 == 0:
            print(f"   Still waiting... ({waited}s)")
    
    if waited >= max_wait:
        print(f"⏱️  Timeout waiting for transaction confirmation")
EOF

if [ $? -ne 0 ]; then
    echo ""
    echo "❌ Transaction failed. Make sure eth-account is installed:"
    echo "   pip3 install eth-account"
    exit 1
fi

echo ""
echo "💰 Checking balances after transfer..."
FROM_BALANCE_HEX_AFTER=$(curl -s -X POST -H "Content-Type: application/json" \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$FROM_ADDRESS\",\"latest\"],\"id\":1}" \
  "$RPC_URL" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

TO_BALANCE_HEX_AFTER=$(curl -s -X POST -H "Content-Type: application/json" \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$TO_ADDRESS\",\"latest\"],\"id\":1}" \
  "$RPC_URL" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

FROM_BALANCE_AFTER=$(printf "%d" $FROM_BALANCE_HEX_AFTER 2>/dev/null || echo "0")
TO_BALANCE_AFTER=$(printf "%d" $TO_BALANCE_HEX_AFTER 2>/dev/null || echo "0")

FROM_BALANCE_ETH_AFTER=$(echo "scale=4; $FROM_BALANCE_AFTER / 1000000000000000000" | bc)
TO_BALANCE_ETH_AFTER=$(echo "scale=4; $TO_BALANCE_AFTER / 1000000000000000000" | bc)

echo "   From balance: $FROM_BALANCE_ETH_AFTER ETH"
echo "   To balance:   $TO_BALANCE_ETH_AFTER ETH"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Test completed successfully!"
echo ""

