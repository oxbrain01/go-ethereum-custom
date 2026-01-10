# Quick Start: Making Transactions with Block Creation

## 🚀 Complete Setup

### Step 1: Start the Node

```bash
./scripts/start-prod/start-prod.sh
```

Wait until you see "✅ Node ready" and "✅ Miner started"

### Step 2: Start Auto-Mining Service (Recommended)

**In a NEW terminal**, run:

```bash
./scripts/start-prod/auto-mine.sh
```

This will monitor for pending transactions and ensure blocks are created automatically.

**Keep this running while you test transactions!**

### Step 3: Send a Transaction

**In another terminal** (or the same as step 1):

```bash
./scripts/start-prod/test-transaction.sh 0.01
```

You should see:
- ✅ Transaction sent successfully
- ✅ Transaction confirmed in block X

## 📋 What Was Fixed

1. ✅ **Transaction scripts** - Fixed raw transaction format and nonce handling
2. ✅ **Auto-mining service** - Monitors and ensures blocks are created
3. ✅ **Automatic mining start** - `start-prod.sh` now starts mining automatically
4. ✅ **Helper scripts** - Easy status checks and block creation

## 🔧 Available Scripts

| Script | Purpose |
|--------|---------|
| `start-prod.sh` | Start the blockchain node |
| `auto-mine.sh` | **Run this to ensure blocks are created** |
| `test-transaction.sh` | Send a test transaction |
| `transfer-balance.sh` | Full-featured transfer script |
| `ensure-blocks.sh` | Quick check and fix block creation |
| `check-blocks.sh` | Check blockchain status |

## 💡 Quick Commands

```bash
# Check if blocks are being created
./scripts/start-prod/check-blocks.sh

# Ensure mining is started
./scripts/start-prod/ensure-blocks.sh

# Send a test transaction
./scripts/start-prod/test-transaction.sh 0.1
```

## 🎯 Expected Flow

1. **Node starts** → Mining automatically starts
2. **Transaction sent** → Enters mempool (pending)
3. **Auto-mining detects** → Ensures mining is active
4. **Block created** → Within 5 seconds (Clique period)
5. **Transaction confirmed** → Included in block

## ⚠️ Troubleshooting

### Blocks not being created?

1. **Check if auto-mining is running:**
   ```bash
   ps aux | grep auto-mine
   ```

2. **Start auto-mining:**
   ```bash
   ./scripts/start-prod/auto-mine.sh
   ```

3. **Check mining status:**
   ```bash
   ./scripts/start-prod/ensure-blocks.sh
   ```

### Transaction stuck?

1. **Check pending transactions:**
   ```bash
   curl -X POST -H "Content-Type: application/json" \
     --data '{"jsonrpc":"2.0","method":"txpool_status","params":[],"id":1}' \
     http://localhost:8547 | python3 -m json.tool
   ```

2. **Check current block:**
   ```bash
   curl -X POST -H "Content-Type: application/json" \
     --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
     http://localhost:8547
   ```

## 📚 More Information

- **Block Creation Guide**: `BLOCK-CREATION-GUIDE.md`
- **Transaction Guide**: `TRANSACTION-GUIDE.md`
- **Make Transaction**: `MAKE-TRANSACTION.md`

## ✅ Success Checklist

- [ ] Node is running (`start-prod.sh`)
- [ ] Auto-mining is running (`auto-mine.sh`) 
- [ ] Mining is active (check with `ensure-blocks.sh`)
- [ ] Transaction sent successfully
- [ ] Block created (check with `check-blocks.sh`)
- [ ] Transaction confirmed

Once all checked, your transactions should work perfectly! 🎉
