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

package poapol

import (
	"errors"
	"math/big"
	"sync"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/vm"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethdb"
	"github.com/ethereum/go-ethereum/log"
)

var (
	errInsufficientDelegation = errors.New("insufficient BGT delegation")
)

// POLState quản lý state liên quan đến POL
type POLState struct {
	db ethdb.Database
	mu sync.RWMutex
}

// NewPOLState tạo một POLState mới
func NewPOLState(db ethdb.Database) *POLState {
	return &POLState{
		db: db,
	}
}

// ValidatorInfo chứa thông tin về validator
type ValidatorInfo struct {
	Address         common.Address
	BGTDelegated   *big.Int // Tổng BGT được ủy quyền
	LiquidityStake *big.Int // Tổng liquidity stake
	TotalRewards   *big.Int // Tổng phần thưởng đã nhận
}

// GetValidatorInfo lấy thông tin validator từ state
func (ps *POLState) GetValidatorInfo(state vm.StateDB, validator common.Address) (*ValidatorInfo, error) {
	ps.mu.RLock()
	defer ps.mu.RUnlock()

	info := &ValidatorInfo{
		Address:         validator,
		BGTDelegated:    big.NewInt(0),
		LiquidityStake:  big.NewInt(0),
		TotalRewards:    big.NewInt(0),
	}

	// Read from state storage slots
	// Storage layout for validator info:
	// slot[0] = BGTDelegated
	// slot[1] = LiquidityStake
	// slot[2] = TotalRewards
	//
	// We use a contract address to store this data
	// In production, you might want to use a dedicated contract or
	// store this in a specific contract's storage

	// For now, we'll use a simple mapping approach
	// In production, you should interact with the BGT contract to get delegation
	bgtSlot := ps.getValidatorSlot(validator, 0)
	liquiditySlot := ps.getValidatorSlot(validator, 1)
	rewardsSlot := ps.getValidatorSlot(validator, 2)

	// Read from state
	// Note: In a real implementation, you would read from the BGT contract
	// For now, we'll use a placeholder contract address
	contractAddr := common.HexToAddress("0x0000000000000000000000000000000000000001")

	bgtHash := state.GetState(contractAddr, bgtSlot)
	liquidityHash := state.GetState(contractAddr, liquiditySlot)
	rewardsHash := state.GetState(contractAddr, rewardsSlot)

	if bgtHash != (common.Hash{}) {
		info.BGTDelegated = new(big.Int).SetBytes(bgtHash.Bytes())
	}
	if liquidityHash != (common.Hash{}) {
		info.LiquidityStake = new(big.Int).SetBytes(liquidityHash.Bytes())
	}
	if rewardsHash != (common.Hash{}) {
		info.TotalRewards = new(big.Int).SetBytes(rewardsHash.Bytes())
	}

	return info, nil
}

// SetValidatorInfo lưu thông tin validator vào state
func (ps *POLState) SetValidatorInfo(state vm.StateDB, info *ValidatorInfo) error {
	ps.mu.Lock()
	defer ps.mu.Unlock()

	// Write to state storage slots
	contractAddr := common.HexToAddress("0x0000000000000000000000000000000000000001")

	bgtSlot := ps.getValidatorSlot(info.Address, 0)
	liquiditySlot := ps.getValidatorSlot(info.Address, 1)
	rewardsSlot := ps.getValidatorSlot(info.Address, 2)

	// Convert big.Int to Hash (truncate if necessary)
	var bgtHash, liquidityHash, rewardsHash common.Hash
	copy(bgtHash[:], info.BGTDelegated.Bytes())
	copy(liquidityHash[:], info.LiquidityStake.Bytes())
	copy(rewardsHash[:], info.TotalRewards.Bytes())

	state.SetState(contractAddr, bgtSlot, bgtHash)
	state.SetState(contractAddr, liquiditySlot, liquidityHash)
	state.SetState(contractAddr, rewardsSlot, rewardsHash)

	return nil
}

// getValidatorSlot tính toán storage slot cho validator
// Uses keccak256(validator_address || index) as slot
func (ps *POLState) getValidatorSlot(validator common.Address, index uint64) common.Hash {
	// Create a key: validator address + index
	key := append(validator.Bytes(), byte(index))
	
	// Hash it to get the slot
	hash := crypto.Keccak256Hash(key)
	return hash
}

// AddBGTDelegation thêm BGT delegation cho validator
func (ps *POLState) AddBGTDelegation(state vm.StateDB, validator common.Address, amount *big.Int) error {
	info, err := ps.GetValidatorInfo(state, validator)
	if err != nil {
		return err
	}

	info.BGTDelegated = new(big.Int).Add(info.BGTDelegated, amount)
	return ps.SetValidatorInfo(state, info)
}

// RemoveBGTDelegation xóa BGT delegation
func (ps *POLState) RemoveBGTDelegation(state vm.StateDB, validator common.Address, amount *big.Int) error {
	info, err := ps.GetValidatorInfo(state, validator)
	if err != nil {
		return err
	}

	if info.BGTDelegated.Cmp(amount) < 0 {
		return errInsufficientDelegation
	}

	info.BGTDelegated = new(big.Int).Sub(info.BGTDelegated, amount)
	return ps.SetValidatorInfo(state, info)
}

// SelectValidator chọn validator để tạo block dựa trên BGT delegation
func (ps *POLState) SelectValidator(state vm.StateDB, validators []common.Address) (common.Address, error) {
	if len(validators) == 0 {
		return common.Address{}, errors.New("no validators available")
	}

	// Calculate total BGT delegation of all validators
	totalDelegation := big.NewInt(0)
	delegations := make(map[common.Address]*big.Int)

	for _, validator := range validators {
		info, err := ps.GetValidatorInfo(state, validator)
		if err != nil {
			log.Debug("Failed to get validator info", "validator", validator, "err", err)
			delegations[validator] = big.NewInt(0)
			continue
		}

		delegations[validator] = info.BGTDelegated
		totalDelegation.Add(totalDelegation, info.BGTDelegated)
	}

	if totalDelegation.Sign() == 0 {
		// If no delegation, fall back to round-robin (POA behavior)
		// This would be handled by Clique's turn-based selection
		return validators[0], nil
	}

	// Weighted selection based on BGT delegation
	// Simplified: select validator with highest delegation
	// In production, you might want to use weighted random selection
	selectedValidator := validators[0]
	maxDelegation := delegations[selectedValidator]

	for validator, delegation := range delegations {
		if delegation.Cmp(maxDelegation) > 0 {
			maxDelegation = delegation
			selectedValidator = validator
		}
	}

	return selectedValidator, nil
}

// GetTotalBGTDelegation returns total BGT delegated across all validators
func (ps *POLState) GetTotalBGTDelegation(state vm.StateDB, validators []common.Address) *big.Int {
	total := big.NewInt(0)
	
	for _, validator := range validators {
		info, err := ps.GetValidatorInfo(state, validator)
		if err != nil {
			continue
		}
		total.Add(total, info.BGTDelegated)
	}
	
	return total
}

