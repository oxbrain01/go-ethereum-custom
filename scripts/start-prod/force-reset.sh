#!/bin/bash
# Force reset blockchain - removes ALL data including state database

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATADIR="${SCRIPT_DIR}/data"

echo "⚠️  WARNING: This will DELETE ALL blockchain data including state database!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📁 Data directory: $DATADIR"
echo ""

# Stop all processes
echo "🛑 Stopping all Geth and beacon simulator processes..."
pkill -f "geth.*start-prod" 2>/dev/null || true
pkill -f "beacon-simulator" 2>/dev/null || true
sleep 2

# Remove entire data directory
if [ -d "$DATADIR" ]; then
    echo "🗑️  Removing ALL blockchain data..."
    rm -rf "$DATADIR"
    echo "✅ All data removed"
fi

# Create fresh data directory
echo "📁 Creating fresh data directory..."
mkdir -p "$DATADIR"

echo ""
echo "✅ Force reset complete!"
echo "💡 Now run ./scripts/start-prod/start-prod.sh to initialize with new genesis block"

