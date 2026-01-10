#!/bin/bash
# Quick script to view the database for start-prod.sh
# Usage: ./view-db.sh [command]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

DATADIR="${SCRIPT_DIR}/data"
GETH_BINARY="./build/bin/geth"

if [ ! -f "$GETH_BINARY" ]; then
    echo "❌ Error: geth binary not found. Run 'make geth' first."
    exit 1
fi

if [ ! -d "$DATADIR/geth/chaindata" ]; then
    echo "❌ Error: Database not found at $DATADIR/geth/chaindata"
    echo "   Make sure you've run start-prod.sh at least once."
    exit 1
fi

# Check if node is running
if pgrep -f "geth.*--config.*config.toml" > /dev/null; then
    echo "⚠️  Warning: Geth node appears to be running."
    echo "   Database inspection may work, but stopping the node is recommended for safety."
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

COMMAND="${1:-metadata}"

case "$COMMAND" in
    metadata|meta)
        echo "📊 Database Metadata:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        "$GETH_BINARY" --datadir "$DATADIR" db metadata
        ;;
    stats|stat)
        echo "📈 Database Statistics:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        "$GETH_BINARY" --datadir "$DATADIR" db stats
        ;;
    inspect)
        echo "🔍 Database Inspection (this may take a while...):"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        "$GETH_BINARY" --datadir "$DATADIR" db inspect
        ;;
    history|hist)
        if [ -z "$2" ]; then
            echo "Usage: $0 history <address> [--start <block>] [--end <block>] [--raw]"
            echo "Example: $0 history 0x356981ee849c96fC40e78B0B22715345E57746fb --start 0 --end 1000 --raw"
            exit 1
        fi
        ADDRESS="$2"
        shift 2
        echo "📜 Account History for $ADDRESS:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        "$GETH_BINARY" --datadir "$DATADIR" db inspect-history "$ADDRESS" "$@"
        ;;
    get)
        if [ -z "$2" ]; then
            echo "Usage: $0 get <hex-key>"
            exit 1
        fi
        echo "🔑 Database Key Value:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        "$GETH_BINARY" --datadir "$DATADIR" db get "$2"
        ;;
    help|--help|-h)
        echo "Database Viewer for start-prod.sh"
        echo ""
        echo "Usage: $0 [command] [options]"
        echo ""
        echo "Commands:"
        echo "  metadata, meta    - Show database metadata (chain status, head block)"
        echo "  stats, stat       - Show database statistics"
        echo "  inspect           - Inspect database contents (detailed breakdown)"
        echo "  history, hist     - View account history"
        echo "                     Usage: $0 history <address> [--start <block>] [--end <block>] [--raw]"
        echo "  get               - Get value of a database key"
        echo "                     Usage: $0 get <hex-key>"
        echo ""
        echo "Examples:"
        echo "  $0 metadata"
        echo "  $0 stats"
        echo "  $0 inspect"
        echo "  $0 history 0x356981ee849c96fC40e78B0B22715345E57746fb --start 0 --end 1000 --raw"
        echo "  $0 get 0x..."
        ;;
    *)
        echo "❌ Unknown command: $COMMAND"
        echo "Run '$0 help' for usage information"
        exit 1
        ;;
esac

