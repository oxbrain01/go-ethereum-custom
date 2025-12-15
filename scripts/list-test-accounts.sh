#!/bin/bash
# Script để liệt kê test accounts và balance

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

TEST_ACCOUNTS_FILE="scripts/test-accounts.json"

if [ ! -f "$TEST_ACCOUNTS_FILE" ]; then
    echo "❌ Test accounts file not found: $TEST_ACCOUNTS_FILE"
    echo "   Run ./scripts/create-test-accounts.sh first"
    exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 TEST ACCOUNTS (5 accounts with 50 ETH each)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if nodes are running
NODE1_RUNNING=$(./build/bin/geth attach --exec "true" --datadir ~/local-testnet-node1 >/dev/null 2>&1 && echo "yes" || echo "no")
NODE2_RUNNING=$(./build/bin/geth attach --exec "true" --datadir ~/local-testnet-node2 >/dev/null 2>&1 && echo "yes" || echo "no")

if [ "$NODE1_RUNNING" = "yes" ]; then
    echo "📊 Checking balances from Node 1:"
    echo ""
    
    # Extract accounts from JSON and check balance
    python3 <<PYTHON_SCRIPT
import json
import subprocess
import sys
import os

with open("$TEST_ACCOUNTS_FILE", "r") as f:
    data = json.load(f)

for i, acc in enumerate(data["accounts"], 1):
    addr = acc["address"]
    password = acc["password"]
    
    # Get balance in wei
    result = subprocess.run(
        ["./build/bin/geth", "attach", "--exec", f"eth.getBalance('{addr}')", "--datadir", os.path.expanduser("~/local-testnet-node1")],
        capture_output=True,
        text=True
    )
    
    if result.returncode == 0:
        balance_str = result.stdout.strip()
        try:
            balance_wei = int(balance_str, 16)  # Convert hex to int
            balance_eth = balance_wei / 10**18
            balance = f"{balance_eth:.2f}"
        except:
            balance = balance_str
    else:
        balance = "N/A"
    
    print(f"   Account {i}: {addr}")
    print(f"      Password: {password}")
    print(f"      Balance: {balance} ETH")
    print("")
PYTHON_SCRIPT
else
    echo "⚠️  Nodes are not running. Showing account info from file:"
    echo ""
    cat "$TEST_ACCOUNTS_FILE" | python3 -m json.tool
    echo ""
    echo "💡 Start nodes to check balances:"
    echo "   ./scripts/restart-and-connect.sh"
fi

