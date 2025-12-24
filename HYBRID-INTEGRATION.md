# Hybrid PoA+PoS Integration Guide

Quick guide to integrate the hybrid consensus engine into your codebase.

## Step 1: Add HybridConsensus Flag to ChainConfig

Add to `params/config.go` in the `ChainConfig` struct:

```go
type ChainConfig struct {
	// ... existing fields ...
	
	// HybridConsensus enables parallel PoA + PoS validation
	// When true, blocks must satisfy both Clique (PoA) and Beacon (PoS) rules
	HybridConsensus bool `json:"hybridConsensus,omitempty"`
}
```

## Step 2: Update CreateConsensusEngine

Modify `eth/ethconfig/config.go`:

```go
import (
	// ... existing imports ...
	"github.com/ethereum/go-ethereum/consensus/hybrid"
)

func CreateConsensusEngine(config *params.ChainConfig, db ethdb.Database) (consensus.Engine, error) {
	if config.TerminalTotalDifficulty == nil {
		log.Error("Geth only supports PoS networks. Please transition legacy networks using Geth v1.13.x.")
		return nil, errors.New("'terminalTotalDifficulty' is not set in genesis block")
	}
	
	// Check for hybrid consensus (parallel PoA + PoS)
	if config.Clique != nil && config.HybridConsensus {
		log.Info("Using hybrid PoA + PoS consensus engine")
		return hybrid.New(config.Clique, config, db), nil
	}
	
	// Original logic: Wrap previously supported consensus engines
	if config.Clique != nil {
		return beacon.New(clique.New(config.Clique, db)), nil
	}
	return beacon.New(ethash.NewFaker()), nil
}
```

## Step 3: Genesis Configuration

Create `genesis-hybrid.json`:

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
    "hybridConsensus": true,
    "clique": {
      "period": 5,
      "epoch": 30000
    },
    "shanghaiTime": 0,
    "cancunTime": 0,
    "depositContractAddress": "0x0000000000000000000000000000000000000000"
  },
  "difficulty": "1",
  "gasLimit": "8000000",
  "extradata": "0x0000000000000000000000000000000000000000000000000000000000000000VALIDATOR1_VALIDATOR2...0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
  "alloc": {
    "VALIDATOR_ADDRESS": {
      "balance": "1000000000000000000000000"
    }
  }
}
```

## Step 4: Build and Run

```bash
# Build
go build -o build/bin/geth ./cmd/geth

# Initialize
./build/bin/geth init --datadir ~/hybrid-node genesis-hybrid.json

# Start
./build/bin/geth \
  --datadir ~/hybrid-node \
  --http \
  --http.api "eth,net,web3,personal,admin,engine" \
  --http.addr "0.0.0.0" \
  --http.port 8545 \
  --unlock "VALIDATOR_ADDRESS" \
  --password ~/hybrid-node/password.txt \
  --allow-insecure-unlock
```

## Verification

```bash
# Check block difficulty (should be 1 or 2)
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest", false],"id":1}' \
  http://localhost:8545 | jq '.result.difficulty'

# Should output: "0x1" or "0x2" (PoA difficulty)
# Block is also validated against PoS rules
```

## How It Works

1. **Block Creation**: Clique validators create blocks with PoA signatures
2. **PoA Validation**: Block must have valid Clique signature (difficulty 1 or 2)
3. **PoS Validation**: Block must also satisfy PoS rules (uncle hash, gas limits, etc.)
4. **Acceptance**: Block is only accepted if BOTH validations pass

## Security Benefits

- ✅ **Defense in Depth**: Attacker must compromise both PoA and PoS
- ✅ **Fast Finality**: 5-15 second block time from PoA
- ✅ **Economic Security**: PoS slashing and staking requirements
- ✅ **Reduced Attack Surface**: Multiple validation layers

## Notes

- Blocks have PoA difficulty (1 or 2) but also satisfy PoS rules
- Clique extra data is allowed (longer than PoS limit) for signatures
- Uncle hash must be empty (PoS requirement)
- All other PoS rules are enforced

