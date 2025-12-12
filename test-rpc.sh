#!/bin/bash
# Script test RPC connection

echo "🔍 Testing RPC connection to localhost:8546..."
echo ""

# Test chain ID
echo "1. Testing eth_chainId..."
RESULT=$(curl -s -X POST http://localhost:8546 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}')

if [ $? -eq 0 ] && [ ! -z "$RESULT" ]; then
  echo "✅ RPC is working!"
  echo "Response: $RESULT"
  echo ""
  
  # Extract chain ID
  CHAIN_ID=$(echo $RESULT | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
  if [ ! -z "$CHAIN_ID" ]; then
    # Convert hex to decimal
    CHAIN_ID_DEC=$(printf "%d" $CHAIN_ID 2>/dev/null || echo "unknown")
    echo "Chain ID (hex): $CHAIN_ID"
    echo "Chain ID (decimal): $CHAIN_ID_DEC"
  fi
else
  echo "❌ RPC is NOT working!"
  echo "Error: Could not connect to http://localhost:8546"
  echo ""
  echo "Possible causes:"
  echo "  1. Node is not running"
  echo "  2. HTTP RPC is not enabled (missing --http flag)"
  echo "  3. Wrong port"
  echo ""
  echo "Solution: Run ./start-dev.sh to start node with HTTP RPC"
fi

echo ""
echo "2. Testing net_version..."
RESULT2=$(curl -s -X POST http://localhost:8546 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}')

if [ $? -eq 0 ] && [ ! -z "$RESULT2" ]; then
  echo "✅ Network version check passed!"
  echo "Response: $RESULT2"
else
  echo "❌ Network version check failed"
fi

echo ""
echo "3. Testing balance of account 0x71562b71999873db5b286df957af199ec94617f7..."
ACCOUNT="0x71562b71999873db5b286df957af199ec94617f7"
RESULT3=$(curl -s -X POST http://localhost:8546 \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$ACCOUNT\",\"latest\"],\"id\":1}")

if [ $? -eq 0 ] && [ ! -z "$RESULT3" ]; then
  # Extract balance hex
  BALANCE_HEX=$(echo $RESULT3 | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
  
  if [ ! -z "$BALANCE_HEX" ]; then
    # Convert hex to decimal (wei) using python for large numbers
    BALANCE_WEI=$(python3 -c "print(int('$BALANCE_HEX', 16))" 2>/dev/null)
    
    if [ ! -z "$BALANCE_WEI" ] && [ "$BALANCE_WEI" != "0" ]; then
      # Convert wei to ETH (divide by 10^18)
      BALANCE_ETH=$(python3 -c "balance_wei = int('$BALANCE_HEX', 16); print('{:.6f}'.format(balance_wei / 10**18))" 2>/dev/null)
      
      if [ ! -z "$BALANCE_ETH" ]; then
        echo "✅ Balance check passed!"
        echo "Account: $ACCOUNT"
        echo "Balance (hex): $BALANCE_HEX"
        echo "Balance (wei): $BALANCE_WEI"
        echo "Balance (ETH): $BALANCE_ETH ETH"
      else
        # Fallback to bc if python fails
        BALANCE_WEI_DEC=$(echo "ibase=16; $(echo $BALANCE_HEX | tr '[:lower:]' '[:upper:]' | sed 's/0X//')" | bc 2>/dev/null)
        if [ ! -z "$BALANCE_WEI_DEC" ]; then
          BALANCE_ETH_BC=$(echo "scale=6; $BALANCE_WEI_DEC / 1000000000000000000" | bc 2>/dev/null)
          echo "✅ Balance check passed!"
          echo "Account: $ACCOUNT"
          echo "Balance (hex): $BALANCE_HEX"
          echo "Balance (wei): $BALANCE_WEI_DEC"
          echo "Balance (ETH): $BALANCE_ETH_BC ETH"
        else
          echo "✅ Balance check passed!"
          echo "Account: $ACCOUNT"
          echo "Balance (hex): $BALANCE_HEX"
        fi
      fi
    else
      echo "⚠️  Account balance is 0"
      echo "Account: $ACCOUNT"
      echo "Balance (hex): $BALANCE_HEX"
    fi
  else
    echo "❌ Could not extract balance from response"
    echo "Response: $RESULT3"
  fi
else
  echo "❌ Balance check failed"
  echo "Error: Could not get balance"
  if [ ! -z "$RESULT3" ]; then
    echo "Response: $RESULT3"
  fi
fi
