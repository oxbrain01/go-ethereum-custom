#!/bin/bash
# Script đơn giản để set balance về 50 ETH bằng geth console

ACCOUNT="0x71562b71999873db5b286df957af199ec94617f7"
TARGET_ETH=50

echo "💰 Setting balance to $TARGET_ETH ETH for account $ACCOUNT"
echo ""
echo "📝 Instructions:"
echo "1. Open geth console in another terminal:"
echo "   ./build/bin/geth attach http://localhost:8546"
echo ""
echo "2. Run these commands in geth console:"
echo ""
echo "   // Unlock account (if needed, password might be empty in dev mode)"
echo "   personal.unlockAccount('$ACCOUNT', '', 0)"
echo ""
echo "   // Get current balance"
echo "   eth.getBalance('$ACCOUNT')"
echo ""
echo "   // Calculate amount to send (current - 50 ETH - 0.1 ETH for gas)"
echo "   var current = eth.getBalance('$ACCOUNT');"
echo "   var target = web3.toWei($TARGET_ETH, 'ether');"
echo "   var gasReserve = web3.toWei(0.1, 'ether');"
echo "   var amount = current.sub(target).sub(gasReserve);"
echo ""
echo "   // Send excess to burn address"
echo "   eth.sendTransaction({"
echo "     from: '$ACCOUNT',"
echo "     to: '0x000000000000000000000000000000000000dead',"
echo "     value: amount"
echo "   })"
echo ""
echo "   // Check new balance"
echo "   eth.getBalance('$ACCOUNT')"
echo ""

# Alternative: Try to do it via RPC if account is already unlocked
echo "🔄 Attempting to set balance via RPC (if account is unlocked)..."
echo ""

# Get current balance
BALANCE_RESULT=$(curl -s -X POST http://localhost:8546 \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$ACCOUNT\",\"latest\"],\"id\":1}")

BALANCE_HEX=$(echo $BALANCE_RESULT | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

if [ -z "$BALANCE_HEX" ]; then
  echo "❌ Could not get balance. Please use geth console method above."
  exit 1
fi

CURRENT_WEI=$(python3 -c "print(int('$BALANCE_HEX', 16))" 2>/dev/null)
TARGET_WEI=$(python3 -c "print(int($TARGET_ETH * 10**18))" 2>/dev/null)
GAS_RESERVE=$(python3 -c "print(int(0.1 * 10**18))" 2>/dev/null)
AMOUNT_TO_SEND=$(python3 -c "print($CURRENT_WEI - $TARGET_WEI - $GAS_RESERVE)" 2>/dev/null)

if [ "$AMOUNT_TO_SEND" -le 0 ]; then
  CURRENT_ETH=$(python3 -c "print('{:.6f}'.format($CURRENT_WEI / 10**18))" 2>/dev/null)
  echo "✅ Balance is already at or below target"
  echo "Current balance: $CURRENT_ETH ETH"
  exit 0
fi

AMOUNT_TO_SEND_HEX=$(python3 -c "print(hex($AMOUNT_TO_SEND))" 2>/dev/null)

echo "Current balance: $(python3 -c "print('{:.6f}'.format($CURRENT_WEI / 10**18))") ETH"
echo "Target balance: $TARGET_ETH ETH"
echo "Amount to send: $(python3 -c "print('{:.6f}'.format($AMOUNT_TO_SEND / 10**18))") ETH"
echo ""

# Try to send transaction (will fail if account is locked)
TX_RESULT=$(curl -s -X POST http://localhost:8546 \
  -H "Content-Type: application/json" \
  -d "{
    \"jsonrpc\":\"2.0\",
    \"method\":\"eth_sendTransaction\",
    \"params\":[{
      \"from\": \"$ACCOUNT\",
      \"to\": \"$BURN_ADDRESS\",
      \"value\": \"$AMOUNT_TO_SEND_HEX\"
    }],
    \"id\":1
  }")

if echo "$TX_RESULT" | grep -q '"result"'; then
  TX_HASH=$(echo $TX_RESULT | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
  echo "✅ Transaction sent! Hash: $TX_HASH"
  echo "Waiting for confirmation..."
  sleep 5
  
  NEW_BALANCE_RESULT=$(curl -s -X POST http://localhost:8546 \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$ACCOUNT\",\"latest\"],\"id\":1}")
  
  NEW_BALANCE_HEX=$(echo $NEW_BALANCE_RESULT | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
  NEW_BALANCE_ETH=$(python3 -c "balance_wei = int('$NEW_BALANCE_HEX', 16); print('{:.6f}'.format(balance_wei / 10**18))" 2>/dev/null)
  
  echo "✅ New balance: $NEW_BALANCE_ETH ETH"
else
  echo "❌ Transaction failed (account might be locked)"
  echo "Response: $TX_RESULT"
  echo ""
  echo "Please use geth console method shown above."
fi
