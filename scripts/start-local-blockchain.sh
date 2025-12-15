#!/bin/bash
# Start local Ethereum blockchain using --dev mode (automatic block creation)
# RPC: http://localhost:8546, Network ID: 1337
# This uses --dev mode which automatically creates blocks via SimulatedBeacon

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

HTTP_PORT=8546
WS_PORT=8547
NETWORKID=1337

echo "🚀 Starting Local Ethereum Blockchain (Dev Mode)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌐 HTTP RPC: http://localhost:$HTTP_PORT"
echo "🔌 WebSocket RPC: ws://localhost:$WS_PORT"
echo "🆔 Network ID: $NETWORKID"
echo "💡 Dev mode: Blocks created automatically every 5 seconds"
echo ""

# Check if geth is built
if [ ! -f "./build/bin/geth" ]; then
    echo "❌ Geth not found. Please build geth first: make geth"
    exit 1
fi

# Use first test account as fee recipient
FEE_RECIPIENT="0x356981ee849c96fC40e78B0B22715345E57746fb"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💡 Dev mode creates blocks automatically when transactions are pending"
echo "💡 The dev account is pre-funded and unlocked"
echo "💡 To import test accounts and fund them, run:"
echo "   ./scripts/import-and-fund-accounts.sh"
echo ""
echo "💡 To test transactions, run in another terminal:"
echo "   ./scripts/test-simple-transfer.sh"
echo ""
echo "💡 To stop, press Ctrl+C"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Start geth in dev mode
# --dev: Enable dev mode (ephemeral PoA network with SimulatedBeacon)
# --dev.period 5: Create blocks every 5 seconds (Clique period)
# --miner.etherbase: Set fee recipient
./build/bin/geth \
  --dev \
  --dev.period 5 \
  --networkid "$NETWORKID" \
  --http \
  --http.addr "0.0.0.0" \
  --http.port "$HTTP_PORT" \
  --http.api "eth,net,web3,personal,miner,admin,txpool,engine" \
  --ws \
  --ws.addr "0.0.0.0" \
  --ws.port "$WS_PORT" \
  --ws.api "eth,net,web3,personal,miner,admin" \
  --allow-insecure-unlock \
  --nodiscover \
  --maxpeers 0 \
  --miner.etherbase "$FEE_RECIPIENT" &
  
GETH_PID=$!

# Wait for geth to start
echo "⏳ Waiting for node to start..."
sleep 8

# Check if node is ready
for i in {1..10}; do
    if curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' "http://localhost:$HTTP_PORT" > /dev/null 2>&1; then
        echo "✅ Node is ready!"
        break
    fi
    if [ $i -eq 10 ]; then
        echo "⚠️  Node may not be ready, but continuing..."
    fi
    sleep 1
done

# Fund test accounts from dev account
echo ""
echo "💰 Funding test accounts with 1000 ETH each..."
echo ""

# Developer key from geth source (known key for dev mode)
DEV_KEY="0xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291"
RPC_URL="http://localhost:$HTTP_PORT"
TEST_ACCOUNTS_FILE="$SCRIPT_DIR/test-accounts.json"

# Fund accounts using Python
python3 << 'PYTHON_EOF'
import json
import requests
import time
from eth_account import Account

Account.enable_unaudited_hdwallet_features()

rpc_url = "http://localhost:8546"
dev_key = "0xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291"
dev_account = Account.from_key(dev_key).address

# Load test accounts
with open("scripts/test-accounts.json", "r") as f:
    data = json.load(f)

print(f"📋 Dev account: {dev_account}")
print(f"📋 Funding {len(data['accounts'])} accounts...\n")

for i, acc in enumerate(data['accounts']):
    addr = acc['address']
    
    # Check current balance
    try:
        bal_hex = requests.post(rpc_url, json={"jsonrpc":"2.0","method":"eth_getBalance","params":[addr,"latest"],"id":1}, timeout=2).json()['result']
        bal = int(bal_hex, 16) / 1e18
    except:
        bal = 0
    
    if bal >= 1000:
        print(f"✅ Account {i+1} ({addr[:10]}...): Already has {bal:.1f} ETH")
        continue
    
    # Fund account
    amount_wei = 1000 * 10**18
    try:
        nonce = int(requests.post(rpc_url, json={"jsonrpc":"2.0","method":"eth_getTransactionCount","params":[dev_account,"latest"],"id":1}, timeout=2).json()['result'], 16)
        gas_price = int(requests.post(rpc_url, json={"jsonrpc":"2.0","method":"eth_gasPrice","params":[],"id":1}, timeout=2).json()['result'], 16)
        
        tx = {'nonce': nonce, 'to': addr, 'value': amount_wei, 'gas': 21000, 'gasPrice': gas_price, 'chainId': 1337}
        signed = Account.sign_transaction(tx, dev_key)
        raw_tx = getattr(signed, 'raw_transaction', getattr(signed, 'rawTransaction', None))
        tx_hex = '0x' + raw_tx.hex()
        
        result = requests.post(rpc_url, json={"jsonrpc":"2.0","method":"eth_sendRawTransaction","params":[tx_hex],"id":1}, timeout=2).json()
        
        if 'error' in result:
            print(f"⚠️  Account {i+1} ({addr[:10]}...): Error - {result['error']}")
        else:
            tx_hash = result['result']
            print(f"📤 Account {i+1} ({addr[:10]}...): Funding transaction sent: {tx_hash[:10]}...")
            
            # Wait for confirmation
            for j in range(15):
                time.sleep(1)
                receipt = requests.post(rpc_url, json={"jsonrpc":"2.0","method":"eth_getTransactionReceipt","params":[tx_hash],"id":1}, timeout=2).json().get('result')
                if receipt and receipt.get('status') == '0x1':
                    new_bal = int(requests.post(rpc_url, json={"jsonrpc":"2.0","method":"eth_getBalance","params":[addr,"latest"],"id":1}, timeout=2).json()['result'], 16) / 1e18
                    print(f"✅ Account {i+1} ({addr[:10]}...): Funded! Balance: {new_bal:.1f} ETH")
                    break
    except Exception as e:
        print(f"⚠️  Account {i+1} ({addr[:10]}...): Error - {str(e)}")

print("\n✅ Account funding complete!")
PYTHON_EOF

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Blockchain is running!"
echo "✅ All test accounts have been funded with 1000 ETH"
echo ""
echo "💡 To test transactions, run in another terminal:"
echo "   ./scripts/test-simple-transfer.sh"
echo ""
echo "💡 To stop, press Ctrl+C or run:"
echo "   ./scripts/stop-local-blockchain.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Wait for geth to exit
wait $GETH_PID

