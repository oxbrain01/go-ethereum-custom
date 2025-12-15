#!/bin/bash
# Stop local Ethereum blockchain

echo "🛑 Stopping local blockchain..."

# Kill geth processes
pkill -f "geth.*--dev" 2>/dev/null
pkill -f "geth.*local-blockchain" 2>/dev/null
pkill -f "beacon-simulator" 2>/dev/null

# Kill processes on ports
lsof -ti:8546 | xargs kill -9 2>/dev/null
lsof -ti:8547 | xargs kill -9 2>/dev/null
lsof -ti:8551 | xargs kill -9 2>/dev/null

sleep 2

# Verify
if ps aux | grep -E "geth.*--dev|geth.*local-blockchain" | grep -v grep > /dev/null; then
    echo "⚠️  Some processes may still be running"
else
    echo "✅ All blockchain processes stopped"
fi

