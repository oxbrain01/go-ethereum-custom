#!/bin/bash
# Import test accounts and fund them from dev account

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

RPC_URL="http://localhost:8546"
TEST_ACCOUNTS_FILE="test-accounts.json"

echo "📥 Importing and funding test accounts..."
echo ""

# Check if node is running
if ! curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' "$RPC_URL" > /dev/null; then
    echo "❌ Node is not running. Please start it first: ./scripts/start-local-blockchain.sh"
    exit 1
fi

# Get dev account
DEV_ACCOUNT=$(curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_coinbase","params":[],"id":1}' "$RPC_URL" | python3 -c "import sys, json; print(json.load(sys.stdin)['result'])")
echo "✅ Dev account: $DEV_ACCOUNT"

# Import accounts and fund them
python3 << 'EOF'
import json
import requests
from eth_account import Account

Account.enable_unaudited_hdwallet_features()
rpc_url = "http://localhost:8546"

# Load test accounts
with open("test-accounts.json", "r") as f:
    data = json.load(f)

dev_account = requests.post(rpc_url, json={"jsonrpc":"2.0","method":"eth_coinbase","params":[],"id":1}).json()['result']
print(f"\n💰 Funding accounts from dev account: {dev_account}")

for i, acc in enumerate(data['accounts']):
    addr = acc['address']
    priv_key = acc['privateKey']
    
    # Check balance
    bal = int(requests.post(rpc_url, json={"jsonrpc":"2.0","method":"eth_getBalance","params":[addr,"latest"],"id":1}).json()['result'], 16) / 1e18
    print(f"\n📋 Account {i+1}: {addr}")
    print(f"   Current balance: {bal} ETH")
    
    if bal < 1000:
        # Fund from dev account
        amount_wei = 1000 * 10**18
        nonce = int(requests.post(rpc_url, json={"jsonrpc":"2.0","method":"eth_getTransactionCount","params":[dev_account,"latest"],"id":1}).json()['result'], 16)
        gas_price = int(requests.post(rpc_url, json={"jsonrpc":"2.0","method":"eth_gasPrice","params":[],"id":1}).json()['result'], 16)
        
        # Use personal_sendTransaction (dev account is unlocked)
        result = requests.post(rpc_url, json={
            "jsonrpc":"2.0",
            "method":"personal_sendTransaction",
            "params":[{
                "from": dev_account,
                "to": addr,
                "value": hex(amount_wei),
                "gas": hex(21000),
                "gasPrice": hex(gas_price)
            }, ""],  # Empty password for dev account
            "id":1
        }).json()
        
        if 'error' in result:
            print(f"   ⚠️  Error: {result['error']}")
        else:
            tx_hash = result['result']
            print(f"   ✅ Funding transaction sent: {tx_hash}")
            print(f"   ⏳ Waiting for confirmation...")
            
            # Wait for transaction
            import time
            for j in range(20):
                time.sleep(1)
                receipt = requests.post(rpc_url, json={"jsonrpc":"2.0","method":"eth_getTransactionReceipt","params":[tx_hash],"id":1}).json().get('result')
                if receipt and receipt.get('status') == '0x1':
                    new_bal = int(requests.post(rpc_url, json={"jsonrpc":"2.0","method":"eth_getBalance","params":[addr,"latest"],"id":1}).json()['result'], 16) / 1e18
                    print(f"   ✅ Funded! New balance: {new_bal} ETH")
                    break
    else:
        print(f"   ✅ Already has sufficient balance")

print("\n✅ All accounts funded!")
EOF

