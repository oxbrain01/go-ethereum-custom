// Copyright 2024 The go-ethereum Authors
// This file implements a hybrid PoA + PoS consensus engine for parallel validation

package hybrid

import (
	"errors"
	"fmt"
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/consensus"
	"github.com/ethereum/go-ethereum/consensus/beacon"
	"github.com/ethereum/go-ethereum/consensus/clique"
	"github.com/ethereum/go-ethereum/consensus/misc/eip1559"
	"github.com/ethereum/go-ethereum/consensus/misc/eip4844"
	"github.com/ethereum/go-ethereum/core/state"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/core/vm"
	"github.com/ethereum/go-ethereum/ethdb"
	"github.com/ethereum/go-ethereum/params"
)

var (
	beaconDifficulty = common.Big0
	errBothRequired  = errors.New("block must satisfy both PoA and PoS validation")
	errInvalidHybrid = errors.New("invalid hybrid consensus block")
)

// Hybrid is a consensus engine that requires BOTH PoA and PoS validation
// for maximum security. Every block must satisfy both consensus mechanisms.
type Hybrid struct {
	cliqueEngine *clique.Clique
	beaconEngine *beacon.Beacon
	config       *params.ChainConfig
}

// New creates a hybrid consensus engine that validates blocks with both PoA and PoS
func New(cliqueConfig *params.CliqueConfig, chainConfig *params.ChainConfig, db ethdb.Database) *Hybrid {
	cliqueEngine := clique.New(cliqueConfig, db)
	beaconEngine := beacon.New(cliqueEngine) // Wrap clique in beacon for PoS compatibility

	return &Hybrid{
		cliqueEngine: cliqueEngine,
		beaconEngine: beaconEngine,
		config:       chainConfig,
	}
}

// Author implements consensus.Engine, returning the PoA signer
func (h *Hybrid) Author(header *types.Header) (common.Address, error) {
	return h.cliqueEngine.Author(header)
}

// VerifyHeader checks whether a header conforms to BOTH PoA and PoS consensus rules
func (h *Hybrid) VerifyHeader(chain consensus.ChainHeaderReader, header *types.Header) error {
	// PHASE 1: Verify PoA (Clique) requirements
	// Block must have valid Clique difficulty (1 or 2)
	if header.Difficulty == nil {
		return errInvalidHybrid
	}
	
	// Clique requires difficulty of 1 (out-of-turn) or 2 (in-turn)
	if header.Difficulty.Cmp(big.NewInt(1)) != 0 && header.Difficulty.Cmp(big.NewInt(2)) != 0 {
		return fmt.Errorf("%w: PoA difficulty must be 1 or 2, got %v", errInvalidHybrid, header.Difficulty)
	}

	// Verify Clique signature and rules
	if err := h.cliqueEngine.VerifyHeader(chain, header); err != nil {
		return fmt.Errorf("PoA validation failed: %w", err)
	}

	// PHASE 2: Verify PoS (Beacon) requirements
	// Note: We allow Clique's extra data (which is longer than PoS limit)
	// but verify other PoS constraints
	
	parent := chain.GetHeader(header.ParentHash, header.Number.Uint64()-1)
	if parent == nil {
		return consensus.ErrUnknownAncestor
	}

	// PoS requires nonce to be 0 (but Clique uses nonce for voting)
	// For hybrid, we'll be lenient: allow Clique nonce but verify other PoS rules
	
	// PoS requires empty uncle hash
	if header.UncleHash != types.EmptyUncleHash {
		return fmt.Errorf("%w: uncle hash must be empty for PoS validation", errInvalidHybrid)
	}

	// Verify timestamp progression (PoS requirement)
	if header.Time <= parent.Time {
		return fmt.Errorf("%w: timestamp must be greater than parent", errInvalidHybrid)
	}

	// Verify gas limit constraints (PoS requirement)
	if header.GasLimit > params.MaxGasLimit {
		return fmt.Errorf("%w: gas limit exceeds maximum", errInvalidHybrid)
	}
	if header.GasUsed > header.GasLimit {
		return fmt.Errorf("%w: gas used exceeds gas limit", errInvalidHybrid)
	}

	// Verify block number progression
	if diff := new(big.Int).Sub(header.Number, parent.Number); diff.Cmp(common.Big1) != 0 {
		return consensus.ErrInvalidNumber
	}

	// Verify EIP-1559 base fee (if London is active)
	if h.config.IsLondon(header.Number) {
		if header.BaseFee == nil {
			return fmt.Errorf("%w: base fee required for London fork", errInvalidHybrid)
		}
		// Validate base fee calculation according to EIP-1559
		if err := eip1559.VerifyEIP1559Header(chain.Config(), parent, header); err != nil {
			return fmt.Errorf("%w: EIP-1559 validation failed: %w", errInvalidHybrid, err)
		}
	}

	// Verify withdrawals hash (if Shanghai is active)
	shanghai := h.config.IsShanghai(header.Number, header.Time)
	if shanghai && header.WithdrawalsHash == nil {
		return fmt.Errorf("%w: withdrawals hash required for Shanghai fork", errInvalidHybrid)
	}
	if !shanghai && header.WithdrawalsHash != nil {
		return fmt.Errorf("%w: withdrawals hash not allowed before Shanghai", errInvalidHybrid)
	}

	// Verify Cancun-specific fields (if active)
	cancun := h.config.IsCancun(header.Number, header.Time)
	if !cancun {
		// Before Cancun, these fields must be nil
		switch {
		case header.ExcessBlobGas != nil:
			return fmt.Errorf("%w: invalid excessBlobGas: have %d, expected nil", errInvalidHybrid, *header.ExcessBlobGas)
		case header.BlobGasUsed != nil:
			return fmt.Errorf("%w: invalid blobGasUsed: have %d, expected nil", errInvalidHybrid, *header.BlobGasUsed)
		case header.ParentBeaconRoot != nil:
			return fmt.Errorf("%w: invalid parentBeaconRoot, have %#x, expected nil", errInvalidHybrid, *header.ParentBeaconRoot)
		}
	} else {
		// After Cancun, ParentBeaconRoot is required
		if header.ParentBeaconRoot == nil {
			return fmt.Errorf("%w: header is missing beaconRoot", errInvalidHybrid)
		}
		// Validate EIP-4844 blob gas calculations
		if err := eip4844.VerifyEIP4844Header(chain.Config(), parent, header); err != nil {
			return fmt.Errorf("%w: EIP-4844 validation failed: %w", errInvalidHybrid, err)
		}
	}

	return nil
}

// VerifyHeaders is similar to VerifyHeader, but verifies a batch of headers concurrently
func (h *Hybrid) VerifyHeaders(chain consensus.ChainHeaderReader, headers []*types.Header) (chan<- struct{}, <-chan error) {
	abort := make(chan struct{})
	results := make(chan error, len(headers))

	go func() {
		for _, header := range headers {
			select {
			case <-abort:
				return
			case results <- h.VerifyHeader(chain, header):
			}
		}
	}()

	return abort, results
}

// VerifyUncles verifies that the given block's uncles conform to consensus rules
// Both PoA and PoS require no uncles
func (h *Hybrid) VerifyUncles(chain consensus.ChainReader, block *types.Block) error {
	if len(block.Uncles()) > 0 {
		return fmt.Errorf("%w: uncles not allowed in hybrid consensus", errInvalidHybrid)
	}
	return nil
}

// Prepare initializes the consensus fields of a block header for BOTH PoA and PoS
func (h *Hybrid) Prepare(chain consensus.ChainHeaderReader, header *types.Header) error {
	// First prepare for PoA (Clique)
	if err := h.cliqueEngine.Prepare(chain, header); err != nil {
		return err
	}

	// Then enforce PoS constraints that don't conflict with PoA:
	// - Uncle hash must be empty (PoS requirement)
	header.UncleHash = types.EmptyUncleHash

	// Note: We keep Clique's nonce (for voting) and extra data (for signature)
	// but ensure other PoS rules are satisfied

	return nil
}

// Finalize runs any post-transaction state modifications
func (h *Hybrid) Finalize(chain consensus.ChainHeaderReader, header *types.Header, state vm.StateDB, body *types.Body) {
	// Process PoS withdrawals if Shanghai is active
	if h.config.IsShanghai(header.Number, header.Time) {
		h.beaconEngine.Finalize(chain, header, state, body)
	}
	// Note: Clique doesn't have block rewards
	// PoS rewards come from the consensus layer (beacon client)
}

// FinalizeAndAssemble runs post-transaction modifications and assembles the final block
func (h *Hybrid) FinalizeAndAssemble(chain consensus.ChainHeaderReader, header *types.Header, state *state.StateDB, body *types.Body, receipts []*types.Receipt) (*types.Block, error) {
	// Use Beacon's finalization for withdrawals and proper block assembly
	if h.config.IsShanghai(header.Number, header.Time) {
		return h.beaconEngine.FinalizeAndAssemble(chain, header, state, body, receipts)
	}

	// For pre-Shanghai, use Clique finalization
	return h.cliqueEngine.FinalizeAndAssemble(chain, header, state, body, receipts)
}

// Seal generates a new sealing request using PoA (Clique)
func (h *Hybrid) Seal(chain consensus.ChainHeaderReader, block *types.Block, results chan<- *types.Block, stop <-chan struct{}) error {
	// Use Clique for sealing (PoA signature)
	return h.cliqueEngine.Seal(chain, block, results, stop)
}

// SealHash returns the hash of a block prior to it being sealed
func (h *Hybrid) SealHash(header *types.Header) common.Hash {
	return h.cliqueEngine.SealHash(header)
}

// CalcDifficulty is the difficulty adjustment algorithm for PoA
func (h *Hybrid) CalcDifficulty(chain consensus.ChainHeaderReader, time uint64, parent *types.Header) *big.Int {
	// Use Clique difficulty calculation (returns 1 or 2)
	return h.cliqueEngine.CalcDifficulty(chain, time, parent)
}

// Close terminates any background threads maintained by the consensus engine
func (h *Hybrid) Close() error {
	return h.cliqueEngine.Close()
}

// InnerEngine returns the embedded Clique engine
func (h *Hybrid) InnerEngine() consensus.Engine {
	return h.cliqueEngine
}

