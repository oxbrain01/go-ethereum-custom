#!/bin/bash
# Script để tạo 5 test accounts với 50 ETH mỗi account trong genesis file
# Sử dụng accounts mặc định từ default-test-accounts.json nếu có

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

GENESIS_FILE="scripts/genesis-2-validators.json"
TEST_ACCOUNTS_FILE="scripts/test-accounts.json"
DEFAULT_ACCOUNTS_FILE="scripts/default-test-accounts.json"

# Check if default accounts exist
if [ -f "$DEFAULT_ACCOUNTS_FILE" ]; then
    echo "📋 Using default test accounts from default-test-accounts.json"
    cp "$DEFAULT_ACCOUNTS_FILE" "$TEST_ACCOUNTS_FILE"
    echo "✅ Loaded default accounts"
    
    # Still need to update genesis file
    echo ""
    echo "📝 Updating genesis file with test accounts..."
    python3 <<PYTHON_SCRIPT
import json

# Read test accounts
with open("$TEST_ACCOUNTS_FILE", "r") as f:
    accounts_data = json.load(f)

# Read genesis
with open("$GENESIS_FILE", "r") as f:
    genesis = json.load(f)

if "alloc" not in genesis:
    genesis["alloc"] = {}

# Add 50 ETH for each account
for acc in accounts_data["accounts"]:
    genesis["alloc"][acc["address"]] = {
        "balance": "50000000000000000000"  # 50 ETH in wei
    }

# Write back
with open("$GENESIS_FILE", "w") as f:
    json.dump(genesis, f, indent=2)

print("✅ Updated genesis file")
PYTHON_SCRIPT
else
    echo "🔧 Creating 5 test accounts with 50 ETH each..."
    echo ""

    # Check if geth is built
if [ ! -f "./build/bin/geth" ]; then
    echo "❌ Geth not found. Building..."
    make geth
fi

# Create temporary directory for account creation
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "📝 Creating 5 new accounts..."
ACCOUNTS=()
PASSWORDS=()

for i in {1..5}; do
    echo "   Creating account $i..."
    
    # Create account with password
    PASSWORD="test$i"
    ACCOUNT_OUTPUT=$(./build/bin/geth account new --datadir "$TEMP_DIR" --password <(echo "$PASSWORD") 2>&1)
    
    if [ $? -ne 0 ]; then
        echo "   ❌ Failed to create account $i"
        exit 1
    fi
    
    # Extract address from output
    ADDRESS=$(echo "$ACCOUNT_OUTPUT" | grep -oE "Address: \{[a-fA-F0-9]{40}\}" | grep -oE "[a-fA-F0-9]{40}" | head -1)
    
    if [ -z "$ADDRESS" ]; then
        # Try alternative method - read from keystore
        KEYSTORE_FILE=$(ls -t "$TEMP_DIR/keystore" 2>/dev/null | head -1)
        if [ -n "$KEYSTORE_FILE" ]; then
            ADDRESS=$(cat "$TEMP_DIR/keystore/$KEYSTORE_FILE" | grep -oE '"address":"[a-fA-F0-9]{40}"' | grep -oE "[a-fA-F0-9]{40}")
        fi
    fi
    
    if [ -z "$ADDRESS" ]; then
        echo "   ❌ Could not extract address for account $i"
        exit 1
    fi
    
    # Convert to checksum address
    ADDRESS="0x${ADDRESS}"
    ACCOUNTS+=("$ADDRESS")
    PASSWORDS+=("$PASSWORD")
    
    echo "   ✅ Account $i: $ADDRESS"
done

echo ""
echo "📝 Saving account info to $TEST_ACCOUNTS_FILE..."
cat > "$TEST_ACCOUNTS_FILE" <<EOF
{
  "accounts": [
EOF

for i in {0..4}; do
    ADDR=${ACCOUNTS[$i]}
    PASS=${PASSWORDS[$i]}
    COMMA=","
    if [ $i -eq 4 ]; then
        COMMA=""
    fi
    cat >> "$TEST_ACCOUNTS_FILE" <<EOF
    {
      "address": "$ADDR",
      "password": "$PASS",
      "balance": "50 ETH"
    }$COMMA
EOF
done

cat >> "$TEST_ACCOUNTS_FILE" <<EOF
  ]
}
EOF

echo "   ✅ Saved account info"
echo ""

# Read existing genesis file
echo "📝 Updating genesis file with test accounts..."

# Create Python script to update genesis
cat > "$TEMP_DIR/update_genesis.py" <<PYTHON_SCRIPT
import json
import sys

# Read genesis file
with open("$GENESIS_FILE", "r") as f:
    genesis = json.load(f)

# Ensure alloc exists
if "alloc" not in genesis:
    genesis["alloc"] = {}

# Add 50 ETH (50 * 10^18 wei) for each test account
accounts = [
$(for addr in "${ACCOUNTS[@]}"; do
    echo "    \"$addr\","
done)
]

for account in accounts:
    genesis["alloc"][account] = {
        "balance": "50000000000000000000"  # 50 ETH in wei
    }

# Write back
with open("$GENESIS_FILE", "w") as f:
    json.dump(genesis, f, indent=2)

print("✅ Updated genesis file with test accounts")
PYTHON_SCRIPT

python3 "$TEMP_DIR/update_genesis.py"

if [ $? -ne 0 ]; then
    echo "❌ Failed to update genesis file"
    exit 1
fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Created 5 test accounts with 50 ETH each:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    for i in {0..4}; do
        echo "   Account $((i+1)): ${ACCOUNTS[$i]} (password: ${PASSWORDS[$i]})"
    done
    echo ""
fi

echo "📄 Account info: $TEST_ACCOUNTS_FILE"
echo "📄 Genesis file updated: $GENESIS_FILE"
echo ""
echo "⚠️  IMPORTANT: Reinitialize nodes to apply genesis changes:"
echo "   ./scripts/reinit-nodes.sh"
echo "   Or manually:"
echo "   rm -rf ~/local-testnet-node1/geth ~/local-testnet-node2/geth"
echo "   ./build/bin/geth --datadir ~/local-testnet-node1 init $GENESIS_FILE"
echo "   ./build/bin/geth --datadir ~/local-testnet-node2 init $GENESIS_FILE"
echo ""

