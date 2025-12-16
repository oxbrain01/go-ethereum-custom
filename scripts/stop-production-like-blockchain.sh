#!/bin/bash
# Stop the production-like local blockchain

set -e

HTTP_PORT=8546

echo "🛑 Stopping Production-Like Local Blockchain..."

# Find and kill geth processes running on the production-like blockchain port
PIDS=$(lsof -ti:$HTTP_PORT 2>/dev/null || true)

if [ -z "$PIDS" ]; then
    echo "ℹ️  No blockchain process found running on port 8546"
    exit 0
fi

echo "📋 Found processes: $PIDS"
for PID in $PIDS; do
    echo "🛑 Stopping process $PID..."
    kill -TERM $PID 2>/dev/null || true
done

# Wait a bit for graceful shutdown
sleep 3

# Force kill if still running
for PID in $PIDS; do
    if kill -0 $PID 2>/dev/null; then
        echo "⚠️  Process $PID still running, force killing..."
        kill -9 $PID 2>/dev/null || true
    fi
done

echo "✅ Blockchain stopped"

