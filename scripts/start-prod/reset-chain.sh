#!/bin/bash
# Script to reset blockchain and reinitialize with new genesis

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATADIR="${SCRIPT_DIR}/data"

echo "⚠️  WARNING: This will DELETE all blockchain data!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📁 Data directory: $DATADIR"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "❌ Cancelled. No changes made."
    exit 0
fi

# Stop node if running
echo "🛑 Stopping any running Geth processes..."
pkill -f "geth.*start-prod" 2>/dev/null || true
pkill -f "beacon-simulator" 2>/dev/null || true
sleep 2

# Remove data directory
if [ -d "$DATADIR" ]; then
    echo "🗑️  Removing old blockchain data..."
    rm -rf "$DATADIR"
    echo "✅ Old data removed"
fi

# Create new data directory
echo "📁 Creating new data directory..."
mkdir -p "$DATADIR"

echo ""
echo "✅ Blockchain data reset complete!"
echo "💡 Now run ./scripts/start-prod/start-prod.sh to initialize with new genesis block"

