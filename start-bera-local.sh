#!/usr/bin/env zsh
set -euo pipefail

# start-bera-local.sh - Build and start bera-geth node

# Parse arguments
DATADIR=${1:-./start-project}
MODE="berachain"
RESET_DATA=false
FORCE_RESTART=false
FOLLOW_LOGS=false

for arg in "$@"; do
  case "$arg" in
    --dev) MODE="dev"; DATADIR=./start-project ;;
    --local) MODE="local"; DATADIR=./start-project ;;
    --reset) MODE="local"; RESET_DATA=true; DATADIR=./start-project ;;
    --force) FORCE_RESTART=true ;;
    --follow) FOLLOW_LOGS=true ;;
    --*) ;;
    *) [[ "$arg" != "$DATADIR" ]] && DATADIR="$arg" ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
BINARY="$BUILD_DIR/bera-geth"
mkdir -p "$DATADIR"
ABS_DATADIR="$(cd "$DATADIR" && pwd)"
LOG="$ABS_DATADIR/bera-geth.log"
PIDFILE="$ABS_DATADIR/bera-geth.pid"
LOCKFILE="$ABS_DATADIR/bera-geth/LOCK"
ESCAPED_DATADIR=$(echo "$ABS_DATADIR" | sed 's/[.[\*^$()+?{|]/\\&/g')

# Find process using this datadir
find_process() {
  local pid
  if [[ -f "$PIDFILE" ]]; then
    pid=$(cat "$PIDFILE" 2>/dev/null)
    if [[ -n "$pid" ]] && ps -p "$pid" >/dev/null 2>&1; then
      local cmd=$(ps -p "$pid" -o command= 2>/dev/null || echo "")
      echo "$cmd" | grep -q "$ABS_DATADIR" && echo "$pid" && return
    fi
  fi
  for pid in $(ps aux | grep "[b]era-geth" | grep -v "start-bera-local" | grep -v "tee" | awk '{print $2}'); do
    local cmd=$(ps -p "$pid" -o command= 2>/dev/null || echo "")
    echo "$cmd" | grep -qE "--datadir[[:space:]=]+[\"]?$ESCAPED_DATADIR[\"]?" && echo "$pid" && return
  done
}

# Stop process
stop_process() {
  local pid=$1
  echo "Stopping existing node (pid=$pid)..."
  kill "$pid" 2>/dev/null || true
  for i in {1..10}; do
    ps -p "$pid" >/dev/null 2>&1 || break
    sleep 1
  done
  echo "✓ Stopped"
}

echo "[1/4] Building bera-geth..."
mkdir -p "$BUILD_DIR"
go build -o "$BINARY" ./cmd/bera-geth || exit 1

echo "[2/4] Preparing datadir..."
RUNNING_PID=$(find_process)

if [[ -n "$RUNNING_PID" ]]; then
  if [[ "$RESET_DATA" == "true" ]] || [[ "$MODE" == "local" ]] || [[ "$FORCE_RESTART" == "true" ]]; then
    stop_process "$RUNNING_PID"
    RUNNING_PID=""
  else
    echo "Node already running (pid=$RUNNING_PID)"
    echo "Use --force to restart or different datadir for multiple instances"
    exit 1
  fi
fi

# Clean stale files
[[ -f "$PIDFILE" ]] && ! ps -p "$(cat "$PIDFILE" 2>/dev/null)" >/dev/null 2>&1 && rm -f "$PIDFILE"
[[ -f "$LOCKFILE" ]] && [[ -z "$(find_process)" ]] && rm -f "$LOCKFILE"

# Reset datadir
if [[ "$RESET_DATA" == "true" ]] || [[ "$MODE" == "local" && -d "$ABS_DATADIR/bera-geth/chaindata" ]]; then
  echo "⚠ Resetting datadir..."
  rm -rf "$ABS_DATADIR/bera-geth" "$PIDFILE" "$LOCKFILE" 2>/dev/null
  echo "✓ Cleared"
fi

# Check lock file
if [[ -f "$LOCKFILE" ]]; then
  LOCK_PID=$(find_process)
  if [[ -n "$LOCK_PID" ]]; then
    if [[ "$FORCE_RESTART" == "true" ]]; then
      stop_process "$LOCK_PID"
      rm -f "$LOCKFILE"
    else
      echo "Lock file exists (pid=$LOCK_PID). Use --force to restart"
      exit 1
    fi
  else
    rm -f "$LOCKFILE"
  fi
fi

# Build args
ARGS=("--datadir" "$ABS_DATADIR")
case "$MODE" in
  dev) ARGS+=("--dev" "--http" "--http.addr" "127.0.0.1" "--http.port" "8549" "--http.api" "eth,net,web3,debug,txpool,personal" "--miner.recommit" "1s") ;;
  local) ARGS+=("--berachain" "--nodiscover" "--maxpeers" "0" "--http" "--http.addr" "127.0.0.1" "--http.port" "8549" "--http.api" "eth,net,web3,debug,txpool" "--ws" "--ws.addr" "127.0.0.1" "--ws.port" "8550") ;;
  *) ARGS+=("--berachain" "--http" "--http.addr" "127.0.0.1" "--http.port" "8549" "--http.api" "eth,net,web3,debug,txpool" "--ws" "--ws.addr" "127.0.0.1" "--ws.port" "8550") ;;
esac

echo "[3/4] Starting bera-geth node..."
if [[ "$FOLLOW_LOGS" == "true" ]]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting (mode: $MODE, foreground)" >> "$LOG"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Node logs (Ctrl+C to stop):"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  "$BINARY" "${ARGS[@]}" 2>&1 | tee -a "$LOG" &
  PID=$!
  echo $PID > "$PIDFILE"
  sleep 2
  echo ""
  echo "Node running. Logs: $LOG"
  echo "RPC: http://127.0.0.1:8549"
  wait $PID
  rm -f "$PIDFILE"
  exit 0
fi

# Background mode
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting (mode: $MODE)" >> "$LOG"
"$BINARY" "${ARGS[@]}" >> "$LOG" 2>&1 &
PID=$!
sleep 1
ACTUAL_PID=$(find_process)
[[ -n "$ACTUAL_PID" ]] && PID=$ACTUAL_PID
echo $PID > "$PIDFILE"
echo "Started (pid=$PID). Waiting for RPC..."

# Wait for RPC
RPC_URL="http://127.0.0.1:8549"
sleep 2
for i in {1..60}; do
  ! ps -p "$PID" >/dev/null 2>&1 && echo "Error: Node stopped. Check $LOG" >&2 && tail -20 "$LOG" >&2 && exit 1
  curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' "$RPC_URL" 2>/dev/null | grep -q 'result' && break
  [[ $i -eq 60 ]] && echo "RPC timeout. Check $LOG" >&2 && tail -20 "$LOG" >&2 && exit 1
  [[ $((i % 10)) -eq 0 ]] && echo "Waiting for RPC... ($i/60s)"
  sleep 1
done

echo "RPC is up"
echo "[$(date +'%Y-%m-%d %H:%M:%S')] RPC available at $RPC_URL" >> "$LOG"

# Verify chain
echo "[4/4] Verifying network..."
if command -v jq >/dev/null 2>&1; then
  CHAIN_ID=$(curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' "$RPC_URL" | jq -r '.result')
  CHAIN_ID_DEC=$(printf "%d" "$CHAIN_ID" 2>/dev/null || echo "$CHAIN_ID")
  echo "Chain ID: $CHAIN_ID_DEC"
  [[ "$MODE" == "berachain" && "$CHAIN_ID_DEC" != "80094" ]] && echo "⚠ Warning: Expected 80094, got $CHAIN_ID_DEC"
else
  curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' "$RPC_URL" | head -1
fi

cat <<-EOF

Node started
Logs: $LOG
PID: $PIDFILE
Stop: kill \$(cat $PIDFILE) && rm -f $PIDFILE
Follow: tail -f $LOG
EOF
exit 0
