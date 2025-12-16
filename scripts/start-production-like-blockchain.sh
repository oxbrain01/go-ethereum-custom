#!/bin/bash
# Start local Ethereum blockchain that closely mimics production
# Uses Proof of Stake (PoS) with SimulatedBeacon, ~12s block time, persistent storage

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

DATADIR="${HOME}/production-like-blockchain"
HTTP_PORT=8546
WS_PORT=8547
P2P_PORT=30303
AUTH_PORT=8551
NETWORKID=1337
GENESIS_FILE="scripts/production-like-genesis.json"
BLOCK_PERIOD=12

echo "🚀 Starting Production-Like Local Ethereum Blockchain"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📁 Data directory: $DATADIR"
echo "🌐 HTTP RPC: http://localhost:$HTTP_PORT"
echo "🔌 WebSocket RPC: ws://localhost:$WS_PORT"
echo "🔐 Auth RPC: http://localhost:$AUTH_PORT"
echo "🆔 Network ID: $NETWORKID"
echo "⏱️  Block period: $BLOCK_PERIOD seconds (production-like)"
echo "💡 Consensus: Proof of Stake (PoS) with SimulatedBeacon"
echo "💡 Storage: Persistent (data saved to disk)"
echo ""

# Check if geth is built
if [ ! -f "./build/bin/geth" ]; then
    echo "❌ Geth not found. Please build geth first: make geth"
    exit 1
fi

# Check if blockchain is initialized
if [ ! -d "$DATADIR/geth" ]; then
    echo "⚠️  Blockchain not initialized. Running setup..."
    ./scripts/setup-production-like-blockchain.sh
    if [ $? -ne 0 ]; then
        echo "❌ Setup failed"
        exit 1
    fi
fi

# Use first test account as fee recipient
FEE_RECIPIENT="0x356981ee849c96fC40e78B0B22715345E57746fb"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Key Differences from Dev Mode:"
echo "   • Proof of Stake (PoS) instead of PoA"
echo "   • Block time: ~12 seconds (vs 5 seconds in dev mode)"
echo "   • Persistent storage (data survives restarts)"
echo "   • Production-like gas limit: 30,000,000"
echo "   • All EIPs and forks enabled from genesis"
echo "   • SimulatedBeacon creates blocks automatically"
echo ""
echo "💡 Pre-funded accounts (1000 ETH each):"
echo "   • 0x356981ee849c96fC40e78B0B22715345E57746fb"
echo "   • 0x3bE69C0DEf08196BEE31D463741Df2B92D3eaf8E"
echo "   • 0xC4fa658C3C835b316CaCB52338eD9ebbce2631D7"
echo "   • 0x1120CFB327baedC2f2638D75Db0935b7f3CC934b"
echo "   • 0x554bdA38d6635155b06Faa43189B52D9eD579f70"
echo ""
echo "💡 To stop, press Ctrl+C or run:"
echo "   ./scripts/stop-production-like-blockchain.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Start geth with production-like settings
# --dev: Enable dev mode with SimulatedBeacon (PoS simulation)
# --dev.period 12: Create blocks every 12 seconds (production-like)
# --datadir: Use persistent storage
# --miner.etherbase: Set fee recipient
./build/bin/geth \
  --dev \
  --dev.period "$BLOCK_PERIOD" \
  --datadir "$DATADIR" \
  --networkid "$NETWORKID" \
  --port "$P2P_PORT" \
  --http \
  --http.addr "0.0.0.0" \
  --http.port "$HTTP_PORT" \
  --http.api "eth,net,web3,personal,miner,admin,txpool,engine,debug" \
  --http.corsdomain "*" \
  --ws \
  --ws.addr "0.0.0.0" \
  --ws.port "$WS_PORT" \
  --ws.api "eth,net,web3,personal,miner,admin" \
  --ws.origins "*" \
  --authrpc.addr "0.0.0.0" \
  --authrpc.port "$AUTH_PORT" \
  --authrpc.vhosts "*" \
  --allow-insecure-unlock \
  --nodiscover \
  --maxpeers 0 \
  --miner.etherbase "$FEE_RECIPIENT" \
  --cache 2048 \
  --cache.database 50 \
  --cache.trie 25 \
  --cache.gc 25 \
  --cache.snapshot 10 &

GETH_PID=$!

# Wait for geth to start
echo "⏳ Waiting for node to start..."
sleep 10

# Check if node is ready
echo "🔍 Checking if node is ready..."
for i in {1..20}; do
    if curl -s -X POST -H "Content-Type: application/json" \
       --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
       "http://localhost:$HTTP_PORT" > /dev/null 2>&1; then
        echo "✅ Node is ready!"
        
        # Get block number
        BLOCK_NUM=$(curl -s -X POST -H "Content-Type: application/json" \
          --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
          "http://localhost:$HTTP_PORT" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
        if [ ! -z "$BLOCK_NUM" ]; then
            BLOCK_DEC=$(printf "%d" "$BLOCK_NUM" 2>/dev/null || echo "0")
            echo "📦 Current block: $BLOCK_DEC"
        fi
        break
    fi
    if [ $i -eq 20 ]; then
        echo "⚠️  Node may not be ready, but continuing..."
    fi
    sleep 1
done

# Fund test accounts from dev account
echo ""
echo "💰 Checking and funding test accounts with 1000 ETH each..."
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

# Pre-funded accounts from genesis
prefunded_accounts = [
    "0x356981ee849c96fC40e78B0B22715345E57746fb",
    "0x3bE69C0DEf08196BEE31D463741Df2B92D3eaf8E",
    "0xC4fa658C3C835b316CaCB52338eD9ebbce2631D7",
    "0x1120CFB327baedC2f2638D75Db0935b7f3CC934b",
    "0x554bdA38d6635155b06Faa43189B52D9eD579f70"
]

print(f"📋 Dev account: {dev_account}")
print(f"📋 Checking {len(prefunded_accounts)} accounts...\n")

for i, addr in enumerate(prefunded_accounts):
    # Check current balance
    try:
        bal_hex = requests.post(rpc_url, json={"jsonrpc":"2.0","method":"eth_getBalance","params":[addr,"latest"],"id":1}, timeout=5).json()['result']
        bal = int(bal_hex, 16) / 1e18
    except Exception as e:
        print(f"⚠️  Account {i+1} ({addr[:10]}...): Error checking balance - {str(e)}")
        continue
    
    if bal >= 1000:
        print(f"✅ Account {i+1} ({addr[:10]}...): Already has {bal:.1f} ETH")
        continue
    
    # Fund account
    amount_wei = 1000 * 10**18
    try:
        nonce = int(requests.post(rpc_url, json={"jsonrpc":"2.0","method":"eth_getTransactionCount","params":[dev_account,"latest"],"id":1}, timeout=5).json()['result'], 16)
        gas_price = int(requests.post(rpc_url, json={"jsonrpc":"2.0","method":"eth_gasPrice","params":[],"id":1}, timeout=5).json()['result'], 16)
        
        tx = {'nonce': nonce, 'to': addr, 'value': amount_wei, 'gas': 21000, 'gasPrice': gas_price, 'chainId': 1337}
        signed = Account.sign_transaction(tx, dev_key)
        raw_tx = getattr(signed, 'raw_transaction', getattr(signed, 'rawTransaction', None))
        tx_hex = '0x' + raw_tx.hex()
        
        result = requests.post(rpc_url, json={"jsonrpc":"2.0","method":"eth_sendRawTransaction","params":[tx_hex],"id":1}, timeout=5).json()
        
        if 'error' in result:
            print(f"⚠️  Account {i+1} ({addr[:10]}...): Error - {result['error']}")
        else:
            tx_hash = result['result']
            print(f"📤 Account {i+1} ({addr[:10]}...): Funding transaction sent: {tx_hash[:10]}...")
            
            # Wait for confirmation (with longer timeout for 12s blocks)
            for j in range(30):
                time.sleep(1)
                receipt = requests.post(rpc_url, json={"jsonrpc":"2.0","method":"eth_getTransactionReceipt","params":[tx_hash],"id":1}, timeout=5).json().get('result')
                if receipt and receipt.get('status') == '0x1':
                    new_bal = int(requests.post(rpc_url, json={"jsonrpc":"2.0","method":"eth_getBalance","params":[addr,"latest"],"id":1}, timeout=5).json()['result'], 16) / 1e18
                    print(f"✅ Account {i+1} ({addr[:10]}...): Funded! Balance: {new_bal:.1f} ETH")
                    break
    except Exception as e:
        print(f"⚠️  Account {i+1} ({addr[:10]}...): Error - {str(e)}")

print("\n✅ Account funding check complete!")
PYTHON_EOF

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Blockchain is running!"
echo ""
echo "🌐 RPC Endpoint: http://localhost:$HTTP_PORT"
echo "🔌 WebSocket: ws://localhost:$WS_PORT"
echo "🔐 Auth RPC: http://localhost:$AUTH_PORT"
echo ""
echo "💡 Example: Get block number"
echo "   curl -X POST -H 'Content-Type: application/json' \\"
echo "     --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' \\"
echo "     http://localhost:$HTTP_PORT"
echo ""
echo "💡 To test transactions, run in another terminal:"
echo "   ./scripts/test-simple-transfer.sh"
echo ""
echo "💡 To stop, press Ctrl+C or run:"
echo "   ./scripts/stop-production-like-blockchain.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Wait for geth to exit
wait $GETH_PID

