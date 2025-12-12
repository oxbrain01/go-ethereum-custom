#!/bin/bash
# Script chạy geth trong developer mode

DATADIR="${HOME}/local-testnet"
HTTP_PORT=8546
WS_PORT=8547

echo "🚀 Starting Geth in developer mode..."
echo "📁 Data directory: $DATADIR"
echo "🌐 HTTP RPC: http://localhost:$HTTP_PORT"
echo "🔌 WebSocket RPC: ws://localhost:$WS_PORT"
echo ""

# Kiểm tra xem geth đã được build chưa
if [ ! -f "./build/bin/geth" ]; then
    echo "❌ Geth not found. Building..."
    make geth
fi

# Chạy geth
./build/bin/geth --dev \
  --datadir "$DATADIR" \
  --http --http.addr "0.0.0.0" --http.port "$HTTP_PORT" \
  --http.api "eth,net,web3,miner,admin" \
  --ws --ws.addr "0.0.0.0" --ws.port "$WS_PORT" \
  --ws.api "eth,net,web3,miner,admin" \
  --allow-insecure-unlock \
  console
