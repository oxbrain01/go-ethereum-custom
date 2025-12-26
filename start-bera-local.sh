#!/usr/bin/env zsh
set -euo pipefail

# start-bera-local.sh
# Convenience script to build bera-geth, create a datadir (default ./start-project),
# start a single node (Berachain preset or dev-mode), wait for RPC and do a quick
# block + PoL check. Designed for macOS (zsh).

usage() {
  cat <<-USAGE
Usage: $0 [DATADIR] [--dev|--local|--reset|--force|--follow]

DATADIR  Path to the data directory (default: ./start-project)
--dev    Run node in --dev mode (fast single-node ephemeral chain)
--local  Start a new local chain from scratch (no mainnet sync, isolated)
--reset  Reset datadir and start fresh local chain (clears existing data)
--force  Force restart: stop existing node and start a new one
--follow Keep script running and tail logs (Ctrl+C to stop)

Examples:
  $0                    # build, create ./start-project, run berachain mainnet node
  $0 ./start-project --dev   # run fast dev-mode node (ephemeral, resets on restart)
  $0 ./start-project --local # start new local chain (persistent, no mainnet sync)
  $0 ./start-project --reset # clear data and start fresh local chain
  $0 ./start-project --force # stop existing node and restart
  $0 ./start-project --follow # start node and tail logs (script keeps running)
USAGE
}

# parse args
DATADIR=${1:-./start-project}
MODE="berachain"
RESET_DATA=false
FORCE_RESTART=false
FOLLOW_LOGS=false

# Check for flags
if [[ ${1:-} == "--dev" || ${1:-} == "--local" || ${1:-} == "--reset" || ${1:-} == "--force" || ${1:-} == "--follow" ]]; then
  if [[ ${1:-} == "--dev" ]]; then
    MODE="dev"
    DATADIR=./start-project
  elif [[ ${1:-} == "--local" ]]; then
    MODE="local"
    DATADIR=./start-project
  elif [[ ${1:-} == "--reset" ]]; then
    MODE="local"
    RESET_DATA=true
    DATADIR=./start-project
  elif [[ ${1:-} == "--force" ]]; then
    FORCE_RESTART=true
    DATADIR=./start-project
  elif [[ ${1:-} == "--follow" ]]; then
    FOLLOW_LOGS=true
    DATADIR=./start-project
  fi
elif [[ ${2:-} == "--dev" ]]; then
  MODE="dev"
elif [[ ${2:-} == "--local" ]]; then
  MODE="local"
elif [[ ${2:-} == "--reset" ]]; then
  MODE="local"
  RESET_DATA=true
elif [[ ${2:-} == "--force" ]]; then
  FORCE_RESTART=true
elif [[ ${2:-} == "--follow" ]]; then
  FOLLOW_LOGS=true
fi

# Check for --follow in any position
for arg in "$@"; do
  if [[ "$arg" == "--follow" ]]; then
    FOLLOW_LOGS=true
  fi
done

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
BINARY="$BUILD_DIR/bera-geth"

echo "root dir: $ROOT_DIR"
echo "datadir: $DATADIR"
echo "mode: $MODE"

# Build
echo "\n[1/4] Building bera-geth..."
mkdir -p "$BUILD_DIR"
go build -o "$BINARY" ./cmd/bera-geth
if [[ ! -x "$BINARY" ]]; then
  echo "Failed to build $BINARY" >&2
  exit 1
fi

echo "Built $BINARY"

# Prepare datadir
echo "\n[2/4] Preparing datadir..."
mkdir -p "$DATADIR"
ABS_DATADIR="$(cd "$DATADIR" && pwd)"
LOG="$ABS_DATADIR/bera-geth.log"
PIDFILE="$ABS_DATADIR/bera-geth.pid"

# Check if node is already running (do this BEFORE clearing data)
RUNNING_BERA_PID=$(ps aux | grep "[b]era-geth" | grep -v "start-bera-local" | grep -v "tee" | grep "$ABS_DATADIR" | awk '{print $2}' | head -1)

if [[ -n "$RUNNING_BERA_PID" ]]; then
  # If resetting, starting local, or force restart, stop the running process
  if [[ "$RESET_DATA" == "true" ]] || [[ "$MODE" == "local" ]] || [[ "$FORCE_RESTART" == "true" ]]; then
    echo "Stopping existing node (pid=$RUNNING_BERA_PID) to start fresh..."
    kill "$RUNNING_BERA_PID" 2>/dev/null || true
    # Wait for process to stop
    for i in {1..10}; do
      if ! ps -p "$RUNNING_BERA_PID" >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done
    echo "✓ Stopped existing node"
    # Clear the variable after stopping
    RUNNING_BERA_PID=""
  else
    echo "Node is already running (pid=$RUNNING_BERA_PID)"
    echo "To stop it: kill $RUNNING_BERA_PID && rm -f $PIDFILE"
    echo "Or use --force to restart: $0 $DATADIR --force"
    exit 1
  fi
fi

# Clean up stale PID file if it exists
if [[ -f "$PIDFILE" ]]; then
  OLD_PID=$(cat "$PIDFILE" 2>/dev/null)
  if ! ps -p "$OLD_PID" >/dev/null 2>&1; then
    echo "Removing stale PID file (process $OLD_PID not found)..."
    rm -f "$PIDFILE"
  fi
fi

# Reset datadir if requested or if starting local chain with existing mainnet data
if [[ "$RESET_DATA" == "true" ]] || [[ "$MODE" == "local" && -d "$ABS_DATADIR/bera-geth/chaindata" ]]; then
  if [[ "$RESET_DATA" == "true" ]]; then
    echo "⚠ Resetting datadir (clearing existing blockchain data)..."
  else
    echo "⚠ Local mode detected with existing chaindata. Clearing to start fresh local chain..."
  fi
  if [[ -d "$ABS_DATADIR/bera-geth" ]]; then
    rm -rf "$ABS_DATADIR/bera-geth"
    echo "✓ Cleared blockchain data"
  fi
  if [[ -f "$PIDFILE" ]]; then
    rm -f "$PIDFILE"
  fi
  if [[ -f "$ABS_DATADIR/bera-geth/LOCK" ]]; then
    rm -f "$ABS_DATADIR/bera-geth/LOCK"
  fi
fi

# Check if datadir is locked by another process
LOCKFILE="$ABS_DATADIR/bera-geth/LOCK"
if [[ -f "$LOCKFILE" ]]; then
  # Re-check for running processes (in case we just stopped one)
  CURRENT_RUNNING_PID=$(ps aux | grep "[b]era-geth" | grep -v "start-bera-local" | grep -v "tee" | grep "$ABS_DATADIR" | awk '{print $2}' | head -1)
  
  if [[ -n "$CURRENT_RUNNING_PID" ]]; then
    # If force restart, stop this process too
    if [[ "$FORCE_RESTART" == "true" ]]; then
      echo "Stopping remaining process (pid=$CURRENT_RUNNING_PID)..."
      kill "$CURRENT_RUNNING_PID" 2>/dev/null || true
      sleep 2
      rm -f "$LOCKFILE"
      echo "✓ Removed lock file"
    else
      echo "Lock file exists and node is running (pid=$CURRENT_RUNNING_PID)"
      echo "To stop it: kill $CURRENT_RUNNING_PID && rm -f $PIDFILE"
      echo "Or use --force to restart: $0 $DATADIR --force"
      exit 1
    fi
  else
    # No valid process found, lock file is stale - remove it
    echo "Removing stale lock file..."
    rm -f "$LOCKFILE"
  fi
fi

# Start node
echo "\n[3/4] Starting bera-geth node (logs -> $LOG)..."
ARGS=("--datadir" "$ABS_DATADIR")
if [[ "$MODE" == "dev" ]]; then
  # Dev mode: ephemeral chain, resets on restart
  ARGS+=("--dev" "--http" "--http.addr" "127.0.0.1" "--http.port" "8549" "--http.api" "eth,net,web3,debug,txpool,personal" "--miner.recommit" "1s")
elif [[ "$MODE" == "local" ]]; then
  # Local mode: new chain from scratch, no mainnet sync, isolated
  # Use berachain config but disable peer discovery to prevent syncing
  ARGS+=("--berachain" "--nodiscover" "--maxpeers" "0" "--http" "--http.addr" "127.0.0.1" "--http.port" "8549" "--http.api" "eth,net,web3,debug,txpool" "--ws" "--ws.addr" "127.0.0.1" "--ws.port" "8550")
else
  # Mainnet mode: sync with berachain mainnet
  ARGS+=("--berachain" "--http" "--http.addr" "127.0.0.1" "--http.port" "8549" "--http.api" "eth,net,web3,debug,txpool" "--ws" "--ws.addr" "127.0.0.1" "--ws.port" "8550")
fi

# Start bera-geth
if [[ "$FOLLOW_LOGS" == "true" ]]; then
  # Foreground mode: show logs in terminal
  echo "Starting bera-geth node in foreground (logs will appear below)..."
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting bera-geth node (mode: $MODE, foreground)" >> "$LOG"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Node logs (Press Ctrl+C to stop):"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  # Start in foreground with tee to show in terminal AND save to log
  "$BINARY" "${ARGS[@]}" 2>&1 | tee -a "$LOG" &
  PID=$!
  echo $PID > "$PIDFILE"
  
  # Wait a moment for process to start
  sleep 2
else
  # Background mode: redirect to log file
  echo "Starting bera-geth node in background..."
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting bera-geth node (mode: $MODE)" >> "$LOG"
  "$BINARY" "${ARGS[@]}" >> "$LOG" 2>&1 &
  PID=$!
  
  # Wait a moment for bera-geth to start, then verify we got the right PID
  sleep 1
  # Find the actual bera-geth process PID to make sure we have the right one
  ACTUAL_PID=$(ps aux | grep "[b]era-geth" | grep -v "start-bera-local" | grep -v "tee" | grep "$ABS_DATADIR" | awk '{print $2}' | head -1)
  if [[ -n "$ACTUAL_PID" ]]; then
    PID=$ACTUAL_PID
  fi
  echo $PID > "$PIDFILE"
  echo "Started bera-geth (pid=$PID). Waiting for RPC to become available..."
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting bera-geth node (mode: $MODE, pid: $PID)" >> "$LOG"
fi

# Wait for RPC (only if not in foreground mode)
if [[ "$FOLLOW_LOGS" != "true" ]]; then
  RPC_URL="http://127.0.0.1:8549"
  # Give the node a moment to fully start
  sleep 2

  for i in {1..60}; do
  # Check if process is still running
  if ! ps -p "$PID" >/dev/null 2>&1; then
    echo "Error: Node process (pid=$PID) has stopped. Check $LOG for errors." >&2
    tail -20 "$LOG" >&2
    exit 1
  fi
  
  # Check if RPC is responding
  RPC_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' "$RPC_URL" 2>/dev/null)
  if echo "$RPC_RESPONSE" | grep -q 'result'; then
    echo "RPC is up"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] RPC endpoint available at $RPC_URL" >> "$LOG"
    break
  fi
  
  if [[ $i -eq 60 ]]; then
    echo "RPC did not become available after 60s; check $LOG" >&2
    echo "Last 20 lines of log:" >&2
    tail -20 "$LOG" >&2
    echo "" >&2
    echo "Testing RPC manually:" >&2
    curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' "$RPC_URL" >&2
    exit 1
  fi
  
    # Show progress every 10 seconds
    if [[ $((i % 10)) -eq 0 ]]; then
      echo "Still waiting for RPC... ($i/60s)"
    fi
    sleep 1
  done
fi

# If in foreground mode, skip RPC verification and just wait
if [[ "$FOLLOW_LOGS" == "true" ]]; then
  RPC_URL="http://127.0.0.1:8549"
  echo ""
  echo "Node is running. Logs are displayed above and saved to: $LOG"
  echo "RPC endpoint: $RPC_URL"
  echo ""
  # Wait for the process (foreground mode)
  wait $PID
  rm -f "$PIDFILE"
  exit 0
fi

# Quick verification: verify chain ID and fetch latest block
echo "\n[4/4] Verifying Berachain network configuration..."
if command -v jq >/dev/null 2>&1; then
  # Verify Chain ID (Berachain mainnet = 80094)
  CHAIN_ID_JSON=$(curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' "$RPC_URL")
  CHAIN_ID_HEX=$(echo "$CHAIN_ID_JSON" | jq -r '.result')
  CHAIN_ID_DEC=$(echo "$CHAIN_ID_HEX" | xargs printf "%d\n" 2>/dev/null || echo "$CHAIN_ID_HEX")
  echo "Chain ID: $CHAIN_ID_DEC (hex: $CHAIN_ID_HEX)"
  
  # Log chain ID to the log file
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Chain ID: $CHAIN_ID_DEC (hex: $CHAIN_ID_HEX)" >> "$LOG"
  if [[ "$MODE" == "berachain" ]]; then
    EXPECTED_CHAIN_ID="0x1387e"  # 80094 in hex
    if [[ "$CHAIN_ID_HEX" == "$EXPECTED_CHAIN_ID" || "$CHAIN_ID_DEC" == "80094" ]]; then
      echo "✓ Verified: Running on Berachain mainnet (Chain ID: 80094)"
      echo "[$(date +'%Y-%m-%d %H:%M:%S')] Verified: Running on Berachain mainnet (Chain ID: 80094)" >> "$LOG"
    else
      echo "⚠ Warning: Expected Chain ID 80094 (Berachain mainnet), but got $CHAIN_ID_DEC"
      echo "[$(date +'%Y-%m-%d %H:%M:%S')] Warning: Expected Chain ID 80094, but got $CHAIN_ID_DEC" >> "$LOG"
    fi
  elif [[ "$MODE" == "local" ]]; then
    echo "✓ Running on local chain (isolated, no mainnet sync)"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Running on local chain (isolated, no mainnet sync)" >> "$LOG"
  elif [[ "$MODE" == "dev" ]]; then
    echo "✓ Running in dev mode (ephemeral chain)"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Running in dev mode (ephemeral chain)" >> "$LOG"
  fi
  
  # Get network info
  NET_VERSION=$(curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' "$RPC_URL" | jq -r '.result')
  echo "Network ID: $NET_VERSION"
  
  # Fetch latest block and inspect transactions (PoL tx usually at index 0 post-fork)
  echo "\nFetching latest block..."
  BLOCK_JSON=$(curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest", true],"id":1}' "$RPC_URL")
  
  BLOCK_NUMBER=$(echo "$BLOCK_JSON" | jq -r '.result.number' | xargs printf "%d\n" 2>/dev/null || echo "$BLOCK_JSON" | jq -r '.result.number')
  BLOCK_HASH=$(echo "$BLOCK_JSON" | jq -r '.result.hash')
  TXCOUNT=$(echo "$BLOCK_JSON" | jq '.result.transactions | length')
  echo "Latest block: #$BLOCK_NUMBER ($BLOCK_HASH)"
  echo "Transaction count: $TXCOUNT"
  
  if [[ $TXCOUNT -gt 0 ]]; then
    FIRST_TXHASH=$(echo "$BLOCK_JSON" | jq -r '.result.transactions[0].hash')
    FIRST_TXTO=$(echo "$BLOCK_JSON" | jq -r '.result.transactions[0].to // "null"')
    echo "First tx: $FIRST_TXHASH"
    if [[ "$FIRST_TXTO" != "null" ]]; then
      echo "  To: $FIRST_TXTO"
    fi
    echo "Full first tx object:" 
    echo "$BLOCK_JSON" | jq '.result.transactions[0]'
  else
    echo "No transactions in latest block"
  fi
else
  echo "jq not found; printing raw responses..."
  CHAIN_ID_JSON=$(curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' "$RPC_URL")
  echo "Chain ID response: $CHAIN_ID_JSON"
  BLOCK_JSON=$(curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest", true],"id":1}' "$RPC_URL")
  echo "Block response (truncated):"
  echo "$BLOCK_JSON" | sed -n '1,200p'
fi

cat <<-EOF

Node started and logs are at: $LOG
PID file: $PIDFILE
To stop the node: kill \\$(cat $PIDFILE) && rm -f $PIDFILE
To follow logs: tail -f $LOG

Notes:
- For a production-like multi-validator setup you'll need to craft a genesis with a beacon validator set and run validator processes. This script starts a single execution node (or a dev node).
- To inspect the PoL tx details, look at the first transaction in the block. The repo implements PoL insertion in miner/worker.go and validation in core/block_validator.go.

EOF

# Script continues here only in background mode
echo ""
echo "Node is running in the background. Use 'tail -f $LOG' to follow logs."
echo "Or restart with --follow to see logs in terminal: $0 $DATADIR --force --follow"
exit 0
