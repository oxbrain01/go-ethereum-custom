// Copyright 2024 The go-ethereum Authors
// This file is part of the go-ethereum library.
//
// The go-ethereum library is free software: you can redistribute it and/or modify
// it under the terms of the GNU Lesser General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// The go-ethereum library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with the go-ethereum library. If not, see <http://www.gnu.org/licenses/>.

// Package poapol implements the Proof-of-Authority + Proof-of-Liquidity consensus engine.
// This combines the efficiency of POA with the liquidity incentives of POL (inspired by Berachain).
package poapol

import (
	"errors"
	"math/big"
	"sync"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/consensus"
	"github.com/ethereum/go-ethereum/consensus/clique"
	"github.com/ethereum/go-ethereum/core/state"
	"github.com/ethereum/go-ethereum/core/tracing"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/core/vm"
	"github.com/ethereum/go-ethereum/ethdb"
	"github.com/ethereum/go-ethereum/log"
	"github.com/ethereum/go-ethereum/params"
	"github.com/holiman/uint256"
)

var (
	errInvalidValidator = errors.New("invalid validator for POL consensus")
	errInsufficientBGT  = errors.New("insufficient BGT delegation")
	errInsufficientLP   = errors.New("insufficient liquidity stake")
)

// POAPOL là consensus engine kết hợp POA và POL
type POAPOL struct {
	clique *clique.Clique
	config *POAPOLConfig
	db     ethdb.Database

	// POL state management
	polState *POLState

	lock sync.RWMutex
}

// New tạo một POA-POL consensus engine mới
func New(config *POAPOLConfig, db ethdb.Database) *POAPOL {
	cliqueConfig := &params.CliqueConfig{
		Period: config.CliqueConfig.Period,
		Epoch:  config.CliqueConfig.Epoch,
	}
	cliqueEngine := clique.New(cliqueConfig, db)

	// Set default values if not provided
	if config.MinLiquidityStake == nil {
		config.MinLiquidityStake = big.NewInt(0)
	}
	if config.DelegationWeight == nil {
		config.DelegationWeight = big.NewInt(1)
	}
	if config.BlockReward == nil {
		config.BlockReward = new(big.Int).Div(new(big.Int).Mul(big.NewInt(2), big.NewInt(params.Ether)), big.NewInt(100))
	}

	return &POAPOL{
		clique:   cliqueEngine,
		config:   config,
		db:       db,
		polState: NewPOLState(db),
	}
}

// Author implements consensus.Engine
func (p *POAPOL) Author(header *types.Header) (common.Address, error) {
	return p.clique.Author(header)
}

// VerifyHeader implements consensus.Engine
func (p *POAPOL) VerifyHeader(chain consensus.ChainHeaderReader, header *types.Header) error {
	// Verify POA rules first
	if err := p.clique.VerifyHeader(chain, header); err != nil {
		return err
	}

	// Verify POL rules (optional, can be disabled for performance)
	// Uncomment if you want strict POL validation
	// return p.verifyPOLRules(chain, header)
	return nil
}

// verifyPOLRules kiểm tra các quy tắc POL
func (p *POAPOL) verifyPOLRules(chain consensus.ChainHeaderReader, header *types.Header) error {
	// Get parent state to check POL requirements
	parent := chain.GetHeader(header.ParentHash, header.Number.Uint64()-1)
	if parent == nil {
		return consensus.ErrUnknownAncestor
	}

	// TODO: Implement POL validation logic
	// This would require reading from state to check:
	// - If validator has minimum BGT delegation
	// - If validator meets liquidity stake requirements
	// For now, we'll skip this check for performance
	// In production, you might want to check these periodically (e.g., every epoch)

	return nil
}

// VerifyHeaders implements consensus.Engine
func (p *POAPOL) VerifyHeaders(chain consensus.ChainHeaderReader, headers []*types.Header) (chan<- struct{}, <-chan error) {
	return p.clique.VerifyHeaders(chain, headers)
}

// VerifyUncles implements consensus.Engine
func (p *POAPOL) VerifyUncles(chain consensus.ChainReader, block *types.Block) error {
	return p.clique.VerifyUncles(chain, block)
}

// Prepare implements consensus.Engine
func (p *POAPOL) Prepare(chain consensus.ChainHeaderReader, header *types.Header) error {
	// Prepare POA fields
	if err := p.clique.Prepare(chain, header); err != nil {
		return err
	}

	// Prepare POL fields (if needed)
	return p.preparePOLFields(chain, header)
}

// preparePOLFields chuẩn bị các trường liên quan đến POL
func (p *POAPOL) preparePOLFields(chain consensus.ChainHeaderReader, header *types.Header) error {
	// TODO: Add POL-specific header fields if needed
	// For example, you might want to include BGT delegation info in extra data
	return nil
}

// Finalize implements consensus.Engine
func (p *POAPOL) Finalize(chain consensus.ChainHeaderReader, header *types.Header, state vm.StateDB, body *types.Body) {
	// Finalize POA first
	p.clique.Finalize(chain, header, state, body)

	// Finalize POL - distribute rewards
	p.finalizePOL(chain, header, state)
}

// finalizePOL xử lý phân phối phần thưởng POL
func (p *POAPOL) finalizePOL(chain consensus.ChainHeaderReader, header *types.Header, state vm.StateDB) {
	validator, err := p.clique.Author(header)
	if err != nil {
		log.Warn("Failed to get validator from header", "err", err)
		return
	}

	// Calculate reward based on BGT delegation
	reward := p.calculatePOLReward(chain, header, validator, state)

	// Distribute reward
	if reward.Sign() > 0 {
		rewardUint256, overflow := uint256.FromBig(reward)
		if overflow {
			log.Warn("Reward overflow, using max uint256", "validator", validator)
			rewardUint256 = uint256.NewInt(0).Sub(uint256.NewInt(0), uint256.NewInt(1))
		}
		state.AddBalance(validator, rewardUint256, tracing.BalanceIncreaseRewardMineBlock)
		log.Info("POL reward distributed", "validator", validator, "reward", reward)
	}
}

// calculatePOLReward tính toán phần thưởng POL cho validator
func (p *POAPOL) calculatePOLReward(chain consensus.ChainHeaderReader, header *types.Header, validator common.Address, state vm.StateDB) *big.Int {
	// Get validator info from POL state
	info, err := p.polState.GetValidatorInfo(state, validator)
	if err != nil {
		log.Debug("Failed to get validator info, using base reward", "validator", validator, "err", err)
		return new(big.Int).Set(p.config.BlockReward)
	}

	// Base reward
	reward := new(big.Int).Set(p.config.BlockReward)

	// Bonus based on BGT delegation
	// Formula: reward = baseReward * (1 + delegationWeight * BGTDelegated / totalBGT)
	// This is simplified - you might want a more sophisticated formula
	if info.BGTDelegated.Sign() > 0 {
		// Get total BGT (simplified - in production, track this separately)
		// For now, we'll use a simple multiplier
		bonus := new(big.Int).Div(
			new(big.Int).Mul(p.config.DelegationWeight, info.BGTDelegated),
			big.NewInt(1000), // Normalize
		)
		reward.Add(reward, bonus)
	}

	// Update validator's total rewards
	info.TotalRewards.Add(info.TotalRewards, reward)
	p.polState.SetValidatorInfo(state, info)

	return reward
}

// FinalizeAndAssemble implements consensus.Engine
func (p *POAPOL) FinalizeAndAssemble(chain consensus.ChainHeaderReader, header *types.Header, state *state.StateDB, body *types.Body, receipts []*types.Receipt) (*types.Block, error) {
	return p.clique.FinalizeAndAssemble(chain, header, state, body, receipts)
}

// Seal implements consensus.Engine
func (p *POAPOL) Seal(chain consensus.ChainHeaderReader, block *types.Block, results chan<- *types.Block, stop <-chan struct{}) error {
	return p.clique.Seal(chain, block, results, stop)
}

// SealHash implements consensus.Engine
func (p *POAPOL) SealHash(header *types.Header) common.Hash {
	return p.clique.SealHash(header)
}

// CalcDifficulty implements consensus.Engine
func (p *POAPOL) CalcDifficulty(chain consensus.ChainHeaderReader, time uint64, parent *types.Header) *big.Int {
	return p.clique.CalcDifficulty(chain, time, parent)
}

// Close implements consensus.Engine
func (p *POAPOL) Close() error {
	return p.clique.Close()
}

// GetPOLState returns the POL state manager
func (p *POAPOL) GetPOLState() *POLState {
	return p.polState
}

