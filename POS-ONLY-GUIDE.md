# Proof of Stake (PoS) Only Configuration Guide

This guide explains how to configure a network that uses **only Proof of Stake (PoS)** consensus from genesis, without PoA or PoW.

## Overview

For **PoS-only consensus**, you need:
1. **Execution Client** (geth) - processes transactions and executes smart contracts
2. **Consensus Client** (Beacon client) - produces PoS blocks and manages validators
3. **Engine API** - communication between execution and consensus clients

## Genesis Configuration

### PoS-Only Genesis File

Create `genesis-pos.json`:

```json
{
  "config": {
    "chainId": 1337,
    "homesteadBlock": 0,
    "eip150Block": 0,
    "eip155Block": 0,
    "eip158Block": 0,
    "byzantiumBlock": 0,
    "constantinopleBlock": 0,
    "petersburgBlock": 0,
    "istanbulBlock": 0,
    "berlinBlock": 0,
    "londonBlock": 0,
    "arrowGlacierBlock": 0,
    "grayGlacierBlock": 0,
    "mergeNetsplitBlock": 0,
    "terminalTotalDifficulty": 0,
    "shanghaiTime": 0,
    "cancunTime": 0,
    "depositContractAddress": "0x0000000000000000000000000000000000000000"
  },
  "difficulty": "0",
  "gasLimit": "30000000",
  "baseFeePerGas": "1000000000",
  "timestamp": "0x0",
  "extraData": "0x",
  "alloc": {
    "0x0000000000000000000000000000000000000001": {
      "balance": "1000000000000000000000000"
    }
  }
}
```

### Key Configuration Parameters

#### 1. Terminal Total Difficulty
```json
"terminalTotalDifficulty": 0
```
- **Set to 0**: Network starts in PoS mode immediately
- **No PoA/PoW phase**: Blocks have difficulty 0 from genesis

#### 2. No Clique Config
```json
// DO NOT include "clique" field
```
- **Omit Clique**: No PoA consensus
- Execution client uses `beacon.New(ethash.NewFaker())`

#### 3. Difficulty
```json
"difficulty": "0"
```
- **Must be 0**: PoS blocks have zero difficulty
- Genesis block also has difficulty 0

#### 4. Extra Data
```json
"extraData": "0x"
```
- **Minimal extra data**: PoS allows max 32 bytes
- No validator addresses needed (handled by Beacon client)

#### 5. Shanghai Time (Withdrawals)
```json
"shanghaiTime": 0
```
- **Set to 0**: Enable withdrawals from genesis
- Required for validator withdrawals

#### 6. Deposit Contract Address
```json
"depositContractAddress": "0x0000000000000000000000000000000000000000"
```
- **Set to actual address**: If deploying deposit contract
- **Or leave as zero**: If using Beacon client's built-in deposit handling

## How It Works

### Consensus Engine Selection

From `eth/ethconfig/config.go`:

```go
func CreateConsensusEngine(config *params.ChainConfig, db ethdb.Database) (consensus.Engine, error) {
    if config.TerminalTotalDifficulty == nil {
        return nil, errors.New("'terminalTotalDifficulty' is not set")
    }
    
    // If Clique is set → PoA wrapped in Beacon
    if config.Clique != nil {
        return beacon.New(clique.New(config.Clique, db)), nil
    }
    
    // If Clique is NOT set → PoS only (Beacon with Ethash faker)
    return beacon.New(ethash.NewFaker()), nil
}
```

**For PoS-only:**
- `config.Clique == nil` → Uses `beacon.New(ethash.NewFaker())`
- All blocks have `difficulty == 0`
- Blocks validated by Beacon PoS rules

## Setup Steps

### Step 1: Initialize Execution Client

```bash
# Initialize blockchain
./build/bin/geth init --datadir ~/execution-node genesis-pos.json

# Verify initialization
ls ~/execution-node/geth/
```

### Step 2: Start Execution Client (Geth)

```bash
./build/bin/geth \
  --datadir ~/execution-node \
  --http \
  --http.api "eth,net,web3,personal,admin,engine" \
  --http.addr "0.0.0.0" \
  --http.port 8545 \
  --ws \
  --ws.api "eth,net,web3,personal,admin,engine" \
  --ws.addr "0.0.0.0" \
  --ws.port 8546 \
  --authrpc.addr "0.0.0.0" \
  --authrpc.port 8551 \
  --authrpc.jwtsecret ~/execution-node/jwt.hex
```

**Important Flags:**
- `--authrpc.*`: Engine API for Beacon client communication
- `--http.api` and `--ws.api`: Include `engine` API
- `--authrpc.jwtsecret`: JWT secret for secure communication

### Step 3: Generate JWT Secret (if not exists)

```bash
# Generate JWT secret
openssl rand -hex 32 > ~/execution-node/jwt.hex

# Share this file with Beacon client
```

### Step 4: Start Consensus Client (Beacon)

You need a Beacon/Consensus client. Examples:

#### Option A: Prysm

```bash
# Install Prysm (example)
# Follow Prysm documentation for installation

# Start Prysm Beacon Node
prysm beacon-node \
  --datadir=~/beacon-node \
  --execution-endpoint=http://localhost:8551 \
  --jwt-secret=~/execution-node/jwt.hex \
  --genesis-state=~/beacon-node/genesis.ssz \
  --chain-config-file=~/beacon-node/config.yaml
```

#### Option B: Lighthouse

```bash
# Install Lighthouse (example)
# Follow Lighthouse documentation for installation

# Start Lighthouse Beacon Node
lighthouse beacon_node \
  --datadir ~/beacon-node \
  --execution-endpoints http://localhost:8551 \
  --checkpoint-sync-url <checkpoint-url> \
  --jwt-secret ~/execution-node/jwt.hex
```

#### Option C: Teku

```bash
# Install Teku (example)
# Follow Teku documentation for installation

# Start Teku Beacon Node
teku \
  --data-path=~/beacon-node \
  --ee-endpoint=http://localhost:8551 \
  --ee-jwt-secret-file=~/execution-node/jwt.hex \
  --network=auto
```

### Step 5: Start Validator Client (Optional)

If you want to participate in consensus:

```bash
# Example with Prysm
prysm validator \
  --datadir=~/validator-node \
  --beacon-rpc-provider=localhost:4000 \
  --wallet-dir=~/validator-wallet \
  --wallet-password-file=~/validator-wallet/password.txt
```

## Verification

### Check Execution Client

```bash
# Get latest block
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest", false],"id":1}' \
  http://localhost:8545 | jq '.result'

# Verify difficulty is 0
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest", false],"id":1}' \
  http://localhost:8545 | jq '.result.difficulty'

# Should output: "0x0"
```

### Check Beacon Client Connection

```bash
# Check Engine API connection (from Beacon client logs)
# Should see: "Connected to execution client"
```

### Check Block Production

```bash
# Monitor block production
watch -n 1 'curl -s -X POST -H "Content-Type: application/json" \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}" \
  http://localhost:8545 | jq -r ".result"'
```

## Complete Example Configuration

### Genesis File (genesis-pos.json)

```json
{
  "config": {
    "chainId": 1337,
    "homesteadBlock": 0,
    "eip150Block": 0,
    "eip155Block": 0,
    "eip158Block": 0,
    "byzantiumBlock": 0,
    "constantinopleBlock": 0,
    "petersburgBlock": 0,
    "istanbulBlock": 0,
    "berlinBlock": 0,
    "londonBlock": 0,
    "arrowGlacierBlock": 0,
    "grayGlacierBlock": 0,
    "mergeNetsplitBlock": 0,
    "terminalTotalDifficulty": 0,
    "shanghaiTime": 0,
    "cancunTime": 0,
    "pragueTime": 0,
    "depositContractAddress": "0x0000000000000000000000000000000000000000"
  },
  "difficulty": "0",
  "gasLimit": "30000000",
  "baseFeePerGas": "1000000000",
  "timestamp": "0x0",
  "extraData": "0x",
  "alloc": {
    "0x0000000000000000000000000000000000000001": {
      "balance": "1000000000000000000000000"
    },
    "0x0000000000000000000000000000000000000002": {
      "balance": "1000000000000000000000000"
    }
  }
}
```

### Execution Client Config (geth.toml)

```toml
[Eth]
NetworkId = 1337
SyncMode = "snap"

[Node]
HTTPHost = "0.0.0.0"
HTTPPort = 8545
WSHost = "0.0.0.0"
WSPort = 8546
AuthAddr = "0.0.0.0"
AuthPort = 8551
AuthVAddr = "0.0.0.0"
AuthVPort = 8551

[Node.P2P]
MaxPeers = 50
```

## Important Notes

### 1. Beacon Client Required

⚠️ **Execution client alone cannot produce blocks!**

- Geth (execution client) processes transactions
- Beacon client produces blocks and manages consensus
- Both must run together

### 2. Engine API

- **Required**: Communication between clients
- **JWT Secret**: Must be shared between clients
- **Port 8551**: Default AuthRPC port

### 3. Validator Setup

For PoS validation, you need:
- **Stake**: Deposit ETH to become validator
- **Validator Client**: Runs validator software
- **Withdrawal Credentials**: For withdrawals

### 4. Block Production

- **Execution Client**: Executes transactions, updates state
- **Consensus Client**: Selects transactions, creates blocks
- **Engine API**: Consensus client sends blocks to execution client

### 5. Network Requirements

- **Execution Layer**: P2P network for transaction propagation
- **Consensus Layer**: P2P network for block proposals
- **Both networks**: Required for full functionality

## Comparison: PoS-Only vs PoA vs Hybrid

| Feature | PoS Only | PoA Only | PoA → PoS | Hybrid |
|---------|----------|----------|-----------|--------|
| Genesis Difficulty | 0 | 1 | 1 | 1 or 2 |
| Block Difficulty | 0 | 1 or 2 | 0 (after TTD) | 1 or 2 |
| Clique Config | ❌ No | ✅ Yes | ✅ Yes | ✅ Yes |
| Beacon Client | ✅ Required | ⚠️ Optional | ✅ Required (post) | ⚠️ Optional |
| Validator Type | Stakers | Signers | Both | Both |
| Security Model | Economic | Authority | Both | Both |

## Troubleshooting

### Issue: No blocks being produced

**Solution:**
- Check Beacon client is running
- Verify Engine API connection
- Check JWT secret is correct
- Ensure validators are active

### Issue: Execution client not connecting to Beacon

**Solution:**
- Verify `--authrpc.*` flags are set
- Check JWT secret file exists and is shared
- Verify ports are not blocked
- Check firewall settings

### Issue: Blocks have difficulty > 0

**Solution:**
- Verify `terminalTotalDifficulty: 0` in genesis
- Ensure no Clique config is set
- Check consensus engine is `beacon.New(ethash.NewFaker())`

### Issue: Withdrawals not working

**Solution:**
- Verify `shanghaiTime: 0` in genesis
- Check withdrawals are enabled in Beacon client
- Verify validator withdrawal credentials

## Summary

**PoS-only configuration:**
1. ✅ Set `terminalTotalDifficulty: 0` in genesis
2. ✅ **Do NOT** include `clique` config
3. ✅ Set `difficulty: "0"` in genesis
4. ✅ Set `shanghaiTime: 0` for withdrawals
5. ✅ Start execution client with Engine API
6. ✅ Start Beacon/Consensus client
7. ✅ Connect clients via Engine API

**Result:** Network runs on pure PoS from genesis, with all blocks having difficulty 0 and validated by Beacon consensus rules.

