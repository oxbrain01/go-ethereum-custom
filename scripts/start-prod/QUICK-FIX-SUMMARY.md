# Quick Fix Summary

## Current Issue
**Error**: `missing trie node ... layer stale`
**Problem**: Genesis state root exists but state trie nodes are missing from database
**Symptom**: Balances are 0, can't create blocks

## Root Cause
The genesis state trie wasn't properly flushed to the database when initializing. The state root hash is in the genesis block header, but the actual account/balance data (trie nodes) are missing.

## Solution

### Option 1: Complete Reset (Recommended)
```bash
# 1. Stop the node and auto-mine (Ctrl+C in both terminals)

# 2. Run complete reset
cd /Users/vinhtv/Documents/g-group/go-ethereum-custom/scripts/start-prod
./complete-reset.sh

# 3. Restart everything
./start-prod.sh
# In another terminal:
./auto-mine.sh

# 4. Wait 10-20 seconds, then test
./test-transaction.sh 0.01
```

### Option 2: Manual Fix
```bash
# 1. Stop node and auto-mine

# 2. Remove database
rm -rf /Users/vinhtv/Documents/g-group/go-ethereum-custom/scripts/start-prod/data/geth

# 3. Re-initialize
cd /Users/vinhtv/Documents/g-group/go-ethereum-custom
./build/bin/geth --datadir scripts/start-prod/data init scripts/start-prod/genesis.json

# 4. Restart node and auto-mine
# 5. Test transaction
```

## Why This Happens
With PathDB (default in newer Geth), the genesis state needs to be properly committed. If the node was started before initialization completed, or if there was an issue during init, the state trie nodes might not be flushed to disk.

## Verification
After fix, you should see:
- Block number > 0
- Validator balance = 1,000,000 ETH
- Transactions can be sent and confirmed
- Blocks are created automatically
