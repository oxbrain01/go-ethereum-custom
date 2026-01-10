#!/bin/bash
# Auto-mining service for Clique PoA
# Uses Python beacon simulator (more reliable than bash)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "🔄 Auto-mining service - using Python beacon simulator..."
echo ""

# Check if Python is available
if ! command -v python3 > /dev/null 2>&1; then
    echo "❌ Error: python3 is required but not found"
    exit 1
fi

exec python3 "$SCRIPT_DIR/beacon-simulator.py"
