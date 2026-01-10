# Blockchain Database Viewing Guide

This guide shows you how to view and inspect the blockchain database in go-ethereum.

## Available Database Commands

The `geth` command-line tool provides several database inspection commands under the `db` subcommand:

### 1. Database Statistics

View overall database statistics:

```bash
./build/bin/geth db stats
```

### 2. Database Inspection

Inspect the storage size for each type of data in the database:

```bash
# Inspect entire database
./build/bin/geth db inspect

# Inspect with prefix filter (hex-encoded)
./build/bin/geth db inspect <prefix>

# Inspect with prefix and start position
./build/bin/geth db inspect <prefix> <start>
```

### 3. Database Metadata

View metadata about the chain status (head block, state root, etc.):

```bash
./build/bin/geth db metadata
```

### 4. Get Database Key

Retrieve the value of a specific database key:

```bash
./build/bin/geth db get <hex-encoded-key>
```

### 5. Inspect State History

Inspect account or storage slot history within a block range:

```bash
# Inspect account history
./build/bin/geth db inspect-history <address> --start <block> --end <block>

# Inspect storage slot history
./build/bin/geth db inspect-history <address> <storage-slot> --start <block> --end <block>

# With raw decoded values
./build/bin/geth db inspect-history <address> --raw
```

### 6. Dump Storage Trie

Show storage key/values of a given storage trie:

```bash
./build/bin/geth db dumptrie <state-root> <account-hash> <storage-trie-root> [start] [max-elements]
```

### 7. Freezer Index

Dump the index of a specific freezer table:

```bash
./build/bin/geth db freezer-index <freezer-type> <table-type> <start> <end>
```

### 8. Check State Content

Verify that state data is cryptographically correct:

```bash
./build/bin/geth db check-state-content [start]
```

## Common Use Cases

### View Database Overview

```bash
./build/bin/geth db stats
./build/bin/geth db metadata
```

### Inspect Database Contents

```bash
# Full inspection
./build/bin/geth db inspect

# Inspect specific data types (use appropriate prefixes)
./build/bin/geth db inspect <prefix>
```

### View Account State History

```bash
# View account history for a specific address
./build/bin/geth db inspect-history 0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb --start 0 --end 1000
```

## Database Key Prefixes

The database uses various prefixes for different data types:

- Headers
- Bodies
- Receipts
- State trie nodes
- Account data
- Storage data
- Transaction lookups
- And more...

Use `db inspect` without arguments to see a breakdown of all data types and their sizes.

## Viewing Database for start-prod.sh

When using `scripts/start-prod/start-prod.sh`, the database is located at:

```
scripts/start-prod/data/geth/chaindata
```

### Quick Helper Script (Easiest Method)

A helper script is available to make viewing the database easier:

```bash
# View database metadata
./scripts/start-prod/view-db.sh metadata

# View database statistics
./scripts/start-prod/view-db.sh stats

# Inspect database contents
./scripts/start-prod/view-db.sh inspect

# View account history
./scripts/start-prod/view-db.sh history 0x356981ee849c96fC40e78B0B22715345E57746fb --start 0 --end 1000 --raw

# Get help
./scripts/start-prod/view-db.sh help
```

### Option 1: Stop the Node First (Recommended)

1. **Stop the running node:**

   ```bash
   # Press Ctrl+C in the terminal running start-prod.sh
   # Or find and kill the process:
   pkill -f "geth.*--config.*config.toml"
   ```

2. **View the database with the correct datadir:**

   ```bash
   # View metadata
   ./build/bin/geth --datadir scripts/start-prod/data db metadata

   # View statistics
   ./build/bin/geth --datadir scripts/start-prod/data db stats

   # Inspect database contents
   ./build/bin/geth --datadir scripts/start-prod/data db inspect

   # View account history
   ./build/bin/geth --datadir scripts/start-prod/data db inspect-history <address> --start 0 --end 1000
   ```

### Option 2: View While Node is Running (Read-Only)

You can inspect the database while the node is running, but be careful:

```bash
# These commands use read-only access
./build/bin/geth --datadir scripts/start-prod/data db metadata
./build/bin/geth --datadir scripts/start-prod/data db stats
./build/bin/geth --datadir scripts/start-prod/data db inspect
```

### Quick Commands for start-prod.sh Database

```bash
# Quick overview
./build/bin/geth --datadir scripts/start-prod/data db metadata

# Detailed inspection
./build/bin/geth --datadir scripts/start-prod/data db inspect

# View validator account (from start-prod.sh)
./build/bin/geth --datadir scripts/start-prod/data db inspect-history 0x356981ee849c96fC40e78B0B22715345E57746fb --start 0 --end 1000 --raw
```

## Notes

- Make sure your geth node is not running when inspecting the database (or use read-only mode)
- The database location is typically in `~/.ethereum/geth/chaindata` (or your custom datadir)
- Use `--datadir` flag to specify a custom database location
- Use `--networkid` or network flags to specify which network's database to inspect
- For `start-prod.sh`, always use `--datadir scripts/start-prod/data` to point to the correct database

## Example Workflow

1. **Check database status:**

   ```bash
   ./build/bin/geth db metadata
   ```

2. **View database statistics:**

   ```bash
   ./build/bin/geth db stats
   ```

3. **Inspect database contents:**

   ```bash
   ./build/bin/geth db inspect
   ```

4. **View specific account history:**
   ```bash
   ./build/bin/geth db inspect-history 0xYourAddress --start 0 --end 1000 --raw
   ```
