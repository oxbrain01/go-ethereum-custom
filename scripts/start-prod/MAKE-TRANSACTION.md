# How to Make a Successful Transaction

## ✅ Transaction Scripts Fixed

I've fixed the transaction scripts and created helper tools:

### Fixed Issues:

1. ✅ Raw transaction format (added 0x prefix)
2. ✅ Nonce handling (uses pending nonce to avoid conflicts)
3. ✅ Better error handling and waiting logic
4. ✅ Transaction confirmation checking

### Available Scripts:

1. **Test Transaction** (recommended for testing):

   ```bash
   ./scripts/start-prod/test-transaction.sh [AMOUNT_ETH]
   ```

   Example: `./scripts/start-prod/test-transaction.sh 0.01`

2. **Transfer Balance** (full-featured):

   ```bash
   ./scripts/start-prod/transfer-balance.sh [FROM] [TO] [AMOUNT_ETH]
   ```

   Example: `./scripts/start-prod/transfer-balance.sh`

3. **Check Blocks**:
   ```bash
   ./scripts/start-prod/check-blocks.sh
   ```

## Current Status

✅ **Transaction sending works!** The scripts can now:

- Sign transactions correctly
- Send them to the node
- Handle nonces properly

⚠️ **Blocks not being created automatically**

The issue is that blocks aren't being created even though transactions are pending. For Clique PoA, blocks should be created automatically when:

- There are pending transactions
- The validator is unlocked
- The validator is authorized in genesis

## Solution: Ensure Blocks Are Created

### Option 1: Check Node Configuration

Make sure your `start-prod.sh` has the validator properly configured:

- ✅ Validator account unlocked (`--unlock`)
- ✅ Validator in genesis `extraData`
- ✅ Miner etherbase set (`--miner.etherbase`)

### Option 2: Manual Block Creation (if needed)

If blocks aren't being created automatically, you might need to trigger them. Check the node logs:

```bash
tail -f scripts/start-prod/start-prod.log
```

Look for:

- Clique signer authorization
- Block creation messages
- Any errors

### Option 3: Verify Validator Setup

Check that the validator address matches in:

1. Genesis `extraData`: `0x356981ee849c96fc40e78b0b22715345e57746fb`
2. `start-prod.sh` validator address
3. Unlocked account

## Testing a Transaction

1. **Start the node** (if not running):

   ```bash
   ./scripts/start-prod/start-prod.sh
   ```

2. **Wait for node to be ready** (should see "✅ Node ready")

3. **Check current status**:

   ```bash
   ./scripts/start-prod/check-blocks.sh
   ```

4. **Send a test transaction**:

   ```bash
   ./scripts/start-prod/test-transaction.sh 0.01
   ```

5. **Monitor blocks**:
   ```bash
   watch -n 1 'curl -s -X POST -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}" http://localhost:8547 | python3 -c "import sys, json; print(int(json.load(sys.stdin).get(\"result\", \"0x0\"), 16))"'
   ```

## Expected Behavior

When a transaction is sent:

1. ✅ Transaction is accepted into mempool
2. ⏳ Clique validator should create a block within 5 seconds
3. ✅ Transaction is included in the block
4. ✅ Transaction is confirmed

## Troubleshooting

### Transaction stuck in pending

If transactions are pending but blocks aren't being created:

1. **Check if validator is creating blocks:**

   ```bash
   tail -f scripts/start-prod/start-prod.log | grep -i "block\|clique\|signer"
   ```

2. **Verify validator is unlocked:**

   ```bash
   curl -X POST -H "Content-Type: application/json" \
     --data '{"jsonrpc":"2.0","method":"eth_accounts","params":[],"id":1}' \
     http://localhost:8547
   ```

3. **Check pending transactions:**
   ```bash
   curl -X POST -H "Content-Type: application/json" \
     --data '{"jsonrpc":"2.0","method":"txpool_content","params":[],"id":1}' \
     http://localhost:8547 | python3 -m json.tool
   ```

### "replacement transaction underpriced"

This means there's already a transaction with the same nonce. The scripts now handle this by using the "pending" nonce, which includes pending transactions.

## Next Steps

The transaction scripts are now working correctly. The remaining issue is ensuring blocks are created automatically. This should happen automatically with Clique PoA when:

- Transactions are pending
- Validator is unlocked and authorized

If blocks still aren't being created, check the node logs for any Clique-specific errors or configuration issues.
