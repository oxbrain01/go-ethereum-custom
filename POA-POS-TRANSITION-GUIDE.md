# PoA to PoS Transition Configuration Guide

This guide explains how to configure a network that starts with **Proof of Authority (Clique)** and transitions to **Proof of Stake (Beacon)**.

## Overview

The codebase supports a **PoA → PoS transition** using:
- **Pre-merge**: Clique (PoA) consensus - blocks have `difficulty > 0` (typically 1 or 2)
- **Post-merge**: Beacon (PoS) consensus - blocks have `difficulty == 0`
- **Transition**: Controlled by `TerminalTotalDifficulty` (TTD)

## How the Transition Works

1. **Pre-merge (PoA)**: Clique validators create blocks with difficulty 1 or 2
2. **Total Difficulty Accumulation**: Each block adds its difficulty to the total
3. **Terminal Block**: When total difficulty reaches `TerminalTotalDifficulty`, the next block is PoS
4. **Post-merge (PoS)**: Beacon consensus takes over, blocks have difficulty 0

## Genesis Configuration

### Step 1: Calculate TerminalTotalDifficulty

First, decide how many PoA blocks you want before transitioning to PoS.

**Formula:**
```
TerminalTotalDifficulty = Number of PoA blocks × Average Difficulty
```

For Clique:
- In-turn validator: difficulty = 2
- Out-of-turn validator: difficulty = 1
- Average ≈ 1.5 (assuming equal validator rotation)

**Example:**
- Want 1000 PoA blocks before transition
- TerminalTotalDifficulty ≈ 1000 × 1.5 = 1500

### Step 2: Create Genesis File

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
    "terminalTotalDifficulty": "1500",
    "clique": {
      "period": 5,
      "epoch": 30000
    },
    "depositContractAddress": "0x0000000000000000000000000000000000000000",
    "shanghaiTime": 0
  },
  "difficulty": "1",
  "gasLimit": "8000000",
  "extradata": "0x0000000000000000000000000000000000000000000000000000000000000000VALIDATOR1_ADDRESS_VALIDATOR2_ADDRESS0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
  "alloc": {
    "VALIDATOR_ADDRESS": {
      "balance": "1000000000000000000000000"
    }
  }
}
```

### Key Configuration Parameters

#### 1. TerminalTotalDifficulty
```json
"terminalTotalDifficulty": "1500"
```
- **NOT 0**: Set to a positive value to enable transition
- **Calculation**: `(desired PoA blocks) × (average difficulty)`
- **Example**: 1000 blocks × 1.5 = 1500

#### 2. Clique Settings (Pre-merge)
```json
"clique": {
  "period": 5,      // Block time in seconds
  "epoch": 30000    // Checkpoint interval
}
```

#### 3. Deposit Contract Address (Optional, for EIP-6110)
```json
"depositContractAddress": "0x0000000000000000000000000000000000000000"
```
- Required if using EIP-6110 validator deposits
- Set to actual contract address if deploying deposit contract

#### 4. Shanghai Time (Required for PoS withdrawals)
```json
"shanghaiTime": 0
```
- Set to 0 to enable withdrawals from genesis
- Or set to a future timestamp to activate later

## Complete Example: 1000 Block PoA → PoS Transition

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
    "terminalTotalDifficulty": "1500",
    "clique": {
      "period": 5,
      "epoch": 30000
    },
    "depositContractAddress": "0x0000000000000000000000000000000000000000",
    "shanghaiTime": 0,
    "cancunTime": 0
  },
  "difficulty": "1",
  "gasLimit": "8000000",
  "extradata": "0x000000000000000000000000000000000000000000000000000000000000000036d84c24395abc90006c3ff19292a54edf591ac3b49433628173fc5b51bf3af6b7f96c8efc1626ec0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
  "alloc": {
    "0x36D84C24395ABC90006C3FF19292a54eDf591ac3": {
      "balance": "1000000000000000000000000"
    },
    "0xB49433628173fc5b51bf3Af6B7F96c8EFc1626EC": {
      "balance": "1000000000000000000000000"
    }
  }
}
```

## Running the Network

### Phase 1: PoA Phase (Pre-merge)

Start nodes with Clique validators:

```bash
# Initialize blockchain
./build/bin/geth init --datadir ~/validator-node genesis.json

# Start PoA validator node
./build/bin/geth \
  --datadir ~/validator-node \
  --http \
  --http.api "eth,net,web3,personal,admin,engine" \
  --http.addr "0.0.0.0" \
  --http.port 8545 \
  --ws \
  --ws.api "eth,net,web3,personal,admin,engine" \
  --ws.addr "0.0.0.0" \
  --ws.port 8546 \
  --unlock "VALIDATOR_ADDRESS" \
  --password ~/validator-node/password.txt \
  --allow-insecure-unlock \
  --authrpc.addr "0.0.0.0" \
  --authrpc.port 8551
```

**During PoA phase:**
- Blocks have difficulty 1 or 2
- Clique validators take turns creating blocks
- Total difficulty accumulates with each block

### Phase 2: Transition Monitoring

Monitor when TTD will be reached:

```bash
# Check current total difficulty
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest", false],"id":1}' \
  http://localhost:8545

# Calculate remaining blocks
# TTD - Current TD = Remaining difficulty
```

### Phase 3: PoS Phase (Post-merge)

**Important**: After TTD is reached, you need a **Beacon/Consensus client** to continue producing blocks.

The execution client (geth) will:
- Accept blocks with difficulty == 0
- Process withdrawals (if Shanghai is active)
- Work with the consensus client via Engine API

**Start with Beacon client connection:**

```bash
# Geth with Engine API (already configured above)
# Connect to your Beacon client (e.g., Prysm, Lighthouse, Teku)

# The Beacon client will:
# 1. Monitor TTD
# 2. Start producing PoS blocks after transition
# 3. Send blocks via Engine API to geth
```

## Transition Detection

The code automatically detects the transition:

```go
// From consensus/beacon/consensus.go
func (beacon *Beacon) VerifyHeader(...) {
    // Pre-merge: difficulty > 0 → use Clique
    if header.Difficulty.Sign() > 0 {
        return beacon.ethone.VerifyHeader(chain, header)
    }
    // Post-merge: difficulty == 0 → use Beacon PoS
    return beacon.verifyHeader(chain, header, parent)
}
```

## Verification

### Check Current Phase

```bash
# Get latest block
BLOCK=$(curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest", false],"id":1}' \
  http://localhost:8545 | jq -r '.result')

# Check difficulty
DIFFICULTY=$(echo $BLOCK | jq -r '.difficulty')

if [ "$DIFFICULTY" == "0x0" ]; then
    echo "✅ Post-merge (PoS) - Block difficulty is 0"
else
    echo "⏳ Pre-merge (PoA) - Block difficulty is $DIFFICULTY"
fi
```

### Check Total Difficulty

```bash
# Get chain status
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest", false],"id":1}' \
  http://localhost:8545 | jq '.result.totalDifficulty'
```

## Important Notes

### 1. TTD Calculation
- **Clique difficulty**: 1 (out-of-turn) or 2 (in-turn)
- **Average**: ~1.5 per block (with equal rotation)
- **Formula**: `TTD = desired_blocks × 1.5`

### 2. Beacon Client Required
- **Pre-merge**: Only execution client (geth) needed
- **Post-merge**: Both execution client (geth) AND consensus client (beacon) needed
- **Engine API**: Required for communication between clients

### 3. Validator Setup
- **PoA validators**: Set in genesis `extradata`
- **PoS validators**: Need to deposit/stake via deposit contract or beacon client

### 4. Transition Point
- The **last block with difficulty > 0** is the terminal PoA block
- The **first block with difficulty == 0** is the first PoS block
- Transition happens automatically when TTD is reached

### 5. No Reversion
- Once transitioned to PoS (difficulty == 0), cannot revert to PoA
- Code enforces: `if parent.Difficulty == 0 && header.Difficulty > 0` → error

## Example Scenarios

### Scenario 1: Quick Transition (100 blocks)
```json
"terminalTotalDifficulty": "150"  // ~100 blocks
```

### Scenario 2: Medium Transition (10,000 blocks)
```json
"terminalTotalDifficulty": "15000"  // ~10,000 blocks
```

### Scenario 3: Long PoA Phase (100,000 blocks)
```json
"terminalTotalDifficulty": "150000"  // ~100,000 blocks
```

## Troubleshooting

### Issue: Blocks stuck at PoA
**Solution**: Check if TTD is set correctly and if total difficulty is accumulating

### Issue: Transition not happening
**Solution**: 
- Verify TTD calculation
- Check if blocks are being produced
- Monitor total difficulty accumulation

### Issue: Post-merge blocks rejected
**Solution**: 
- Ensure Beacon client is connected
- Verify Engine API is enabled
- Check Shanghai time is set correctly

## Summary

1. **Set TTD > 0** in genesis (not 0!)
2. **Calculate TTD**: `desired_blocks × 1.5`
3. **Start with PoA**: Clique validators create blocks
4. **Monitor TTD**: Watch total difficulty approach TTD
5. **Prepare Beacon client**: Set up before transition
6. **Transition happens**: Automatically when TTD reached
7. **Post-merge**: Beacon client produces PoS blocks

The transition is **automatic** - no manual intervention needed once TTD is reached!

