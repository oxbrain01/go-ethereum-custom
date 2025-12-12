#!/bin/bash
# Script để set balance của account về 50 ETH
# Usage: ./set-balance-50eth.sh [account_address] [target_eth]

ACCOUNT="${1:-0x71562b71999873db5b286df957af199ec94617f7}"
TARGET_ETH="${2:-50}"
BURN_ADDRESS="0x000000000000000000000000000000000000dead"  # Burn address

echo "💰 Setting balance to $TARGET_ETH ETH for account $ACCOUNT"
echo ""

# Get current balance
echo "1. Getting current balance..."
BALANCE_RESULT=$(curl -s -X POST http://localhost:8546 \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$ACCOUNT\",\"latest\"],\"id\":1}")

BALANCE_HEX=$(echo $BALANCE_RESULT | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

if [ -z "$BALANCE_HEX" ]; then
  echo "❌ Could not get balance"
  exit 1
fi

# Convert to wei
CURRENT_WEI=$(python3 -c "print(int('$BALANCE_HEX', 16))" 2>/dev/null)
TARGET_WEI=$(python3 -c "print(int($TARGET_ETH * 10**18))" 2>/dev/null)

echo "Current balance: $(python3 -c "print('{:.6f}'.format($CURRENT_WEI / 10**18))") ETH"
echo "Target balance: $TARGET_ETH ETH"
echo ""

# Calculate amount to send (current - target - gas)
# We'll send (current - target - 0.1 ETH for gas) to burn address
GAS_RESERVE=$(python3 -c "print(int(0.1 * 10**18))" 2>/dev/null)
AMOUNT_TO_SEND=$(python3 -c "print($CURRENT_WEI - $TARGET_WEI - $GAS_RESERVE)" 2>/dev/null)

if [ "$AMOUNT_TO_SEND" -le 0 ]; then
  echo "✅ Balance is already at or below $TARGET_ETH ETH"
  exit 0
fi

AMOUNT_TO_SEND_HEX=$(python3 -c "print(hex($AMOUNT_TO_SEND))" 2>/dev/null)

echo "2. Sending excess balance to burn address..."
echo "Amount to send: $(python3 -c "print('{:.6f}'.format($AMOUNT_TO_SEND / 10**18))") ETH"
echo ""

# Send transaction
TX_RESULT=$(curl -s -X POST http://localhost:8546 \
  -H "Content-Type: application/json" \
  -d "{
    \"jsonrpc\":\"2.0\",
    \"method\":\"eth_sendTransaction\",
    \"params\":[{
      \"from\": \"$ACCOUNT\",
      \"to\": \"$BURN_ADDRESS\",
      \"value\": \"$AMOUNT_TO_SEND_HEX\",
      \"gas\": \"0x5208\",
      \"gasPrice\": \"0x3b9aca00\"
    }],
    \"id\":1
  }")

TX_HASH=$(echo $TX_RESULT | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

if [ -z "$TX_HASH" ]; then
  echo "❌ Transaction failed"
  echo "Response: $TX_RESULT"
  echo ""
  echo "Note: Account might need to be unlocked. Try unlocking in geth console:"
  echo "  personal.unlockAccount('$ACCOUNT', 'password', 0)"
  exit 1
fi

echo "✅ Transaction sent!"
echo "Transaction hash: $TX_HASH"
echo ""
echo "3. Waiting for transaction to be mined..."
sleep 5

# Check new balance
echo ""
echo "4. Checking new balance..."
NEW_BALANCE_RESULT=$(curl -s -X POST http://localhost:8546 \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$ACCOUNT\",\"latest\"],\"id\":1}")

NEW_BALANCE_HEX=$(echo $NEW_BALANCE_RESULT | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
NEW_BALANCE_WEI=$(python3 -c "print(int('$NEW_BALANCE_HEX', 16))" 2>/dev/null)
NEW_BALANCE_ETH=$(python3 -c "print('{:.6f}'.format($NEW_BALANCE_WEI / 10**18))" 2>/dev/null)

echo "New balance: $NEW_BALANCE_ETH ETH"
echo ""

# Check if close to target
DIFF=$(python3 -c "print(abs($NEW_BALANCE_ETH - $TARGET_ETH))" 2>/dev/null)
if [ $(python3 -c "print($DIFF < 1)" 2>/dev/null) = "True" ]; then
  echo "✅ Balance set successfully! (within 1 ETH of target)"
else
  echo "⚠️  Balance is $NEW_BALANCE_ETH ETH (target: $TARGET_ETH ETH)"
  echo "   Difference: $DIFF ETH"
fi
