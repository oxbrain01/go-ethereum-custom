#!/bin/bash
# Script chạy geth node cho private network

DATADIR="${HOME}/local-testnet"
HTTP_PORT=8546
WS_PORT=8547
NETWORKID=1337

echo "🚀 Starting Geth node..."
echo "📁 Data directory: $DATADIR"
echo "🌐 HTTP RPC: http://localhost:$HTTP_PORT"
echo "🔌 WebSocket RPC: ws://localhost:$WS_PORT"
echo "🆔 Network ID: $NETWORKID"
echo ""

# Kiểm tra xem geth đã được build chưa
if [ ! -f "./build/bin/geth" ]; then
    echo "❌ Geth not found. Building..."
    make geth
fi

# Kiểm tra data directory
if [ ! -d "$DATADIR" ]; then
    echo "❌ Data directory not found: $DATADIR"
    echo "Please run ./setup-private-net.sh first"
    exit 1
fi

# Chạy geth
./build/bin/geth \
  --datadir "$DATADIR" \
  --networkid "$NETWORKID" \
  --http --http.addr "0.0.0.0" --http.port "$HTTP_PORT" \
  --http.api "eth,net,web3,miner,admin" \
  --ws --ws.addr "0.0.0.0" --ws.port "$WS_PORT" \
  --ws.api "eth,net,web3,miner,admin" \
  --allow-insecure-unlock \
  console
