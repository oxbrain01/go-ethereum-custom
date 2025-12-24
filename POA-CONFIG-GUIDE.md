# Proof of Authority (PoA) Configuration Guide

This guide explains how to configure Clique (PoA) consensus in your go-ethereum-custom setup.

## Overview

The codebase uses **Beacon-wrapped Clique** for PoA consensus. This means:

- Clique handles the PoA logic
- Beacon wrapper ensures compatibility with post-merge Ethereum
- **Important**: `terminalTotalDifficulty` must be set (even if 0) for the code to work

## Genesis File Configuration

### Required Fields

Create a `genesis.json` file with the following structure:

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
    "clique": {
      "period": 5,
      "epoch": 30000
    }
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

#### 1. Clique Settings

```json
"clique": {
  "period": 5,      // Block time in seconds (minimum time between blocks)
  "epoch": 30000    // Number of blocks before resetting votes and checkpoint
}
```

- **period**: Time between blocks in seconds (recommended: 5-15 seconds)
- **epoch**: Checkpoint interval (default: 30000 blocks)

#### 2. Terminal Total Difficulty (REQUIRED)

```json
"terminalTotalDifficulty": 0
```

**This is mandatory!** Even for PoA networks, you must set this field. Setting it to `0` means the network starts in PoS mode immediately.

#### 3. ExtraData Format

The `extradata` field contains the initial validator addresses. Format:

```
0x + [32 bytes of zeros] + [validator addresses (20 bytes each)] + [32 bytes of zeros]
```

**Example with 2 validators:**

```bash
# Validator 1: 0x36D84C24395ABC90006C3FF19292a54eDf591ac3
# Validator 2: 0xB49433628173fc5b51bf3Af6B7F96c8EFc1626EC

# extradata:
0x0000000000000000000000000000000000000000000000000000000000000000
36d84c24395abc90006c3ff19292a54edf591ac3
b49433628173fc5b51bf3af6b7f96c8efc1626ec
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
```

**Script to generate extradata:**

```bash
#!/bin/bash
# Generate extradata for Clique validators

# Input validator addresses (without 0x prefix)
VALIDATORS=(
  "36d84c24395abc90006c3ff19292a54edf591ac3"
  "b49433628173fc5b51bf3af6b7f96c8efc1626ec"
)

# Build extradata
EXTRADATA="0x"
# 32 bytes of zeros (64 hex chars)
EXTRADATA+="0000000000000000000000000000000000000000000000000000000000000000"
# Validator addresses (40 hex chars each)
for addr in "${VALIDATORS[@]}"; do
  EXTRADATA+="${addr}"
done
# 32 bytes of zeros (64 hex chars)
EXTRADATA+="0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"

echo "$EXTRADATA"
```

## Complete Example

Here's a complete example for a 2-validator setup:

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
    "clique": {
      "period": 5,
      "epoch": 30000
    }
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

## Initializing the Chain

After creating your `genesis.json`:

```bash
# Initialize the blockchain
./build/bin/geth init --datadir ~/validator-node genesis.json

# Start the node (with validator account unlocked)
./build/bin/geth \
  --datadir ~/validator-node \
  --http \
  --http.api "eth,net,web3,personal,admin" \
  --http.addr "0.0.0.0" \
  --http.port 8545 \
  --unlock "VALIDATOR_ADDRESS" \
  --password ~/validator-node/password.txt \
  --allow-insecure-unlock
```

## Important Notes

1. **TerminalTotalDifficulty is Required**: Even though you're using PoA, the code requires `terminalTotalDifficulty` to be set. This is because the codebase only supports post-merge networks.

2. **Beacon Wrapper**: Clique is automatically wrapped in Beacon consensus engine. This is handled in `CreateConsensusEngine()` function.

3. **Validator Accounts**: Each validator needs:

   - An account with ETH balance
   - The account address included in `extradata`
   - The account unlocked when running the node

4. **Adding/Removing Validators**: After genesis, validators can vote to add/remove other validators using special nonce values:

   - `0xffffffffffffffff` - Vote to add a validator
   - `0x0000000000000000` - Vote to remove a validator

5. **Block Time**: The `period` setting controls minimum block time. Validators take turns creating blocks.

## Verification

After starting your node, verify PoA is working:

```bash
# Check latest block
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest", true],"id":1}' \
  http://localhost:8545

# Check consensus engine
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["0", false],"id":1}' \
  http://localhost:8545
```

The block difficulty should be `0x1` or `0x2` (not `0x0`), indicating Clique PoA is active.

---

## PoA to PoS Transition

If you want to configure a network that **starts with PoA and transitions to PoS**, see the detailed guide:

📖 **[PoA to PoS Transition Guide](./POA-POS-TRANSITION-GUIDE.md)**

Key difference: Set `terminalTotalDifficulty` to a **positive value** (not 0) to enable the transition.
