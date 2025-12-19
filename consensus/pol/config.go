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
	"fmt"
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/params"
)

// POAPOLConfig là cấu hình cho POA + POL consensus
// Nó kế thừa từ CliqueConfig và thêm các trường POL
type POAPOLConfig struct {
	CliqueConfig       *params.CliqueConfig // Clique configuration
	// POL specific configs
	BGTContractAddress common.Address `json:"bgtContractAddress"` // Địa chỉ contract BGT token
	RewardVaultAddress common.Address `json:"rewardVaultAddress"` // Địa chỉ Reward Vault contract
	MinLiquidityStake  *big.Int       `json:"minLiquidityStake"`  // Minimum liquidity stake required
	DelegationWeight   *big.Int       `json:"delegationWeight"`   // Weight of BGT delegation in validator selection
	BlockReward        *big.Int       `json:"blockReward"`         // Block reward for validators
}

// NewPOAPOLConfig tạo một POAPOLConfig mới với các giá trị mặc định
func NewPOAPOLConfig(cliqueConfig *params.CliqueConfig) *POAPOLConfig {
	return &POAPOLConfig{
		CliqueConfig:       cliqueConfig,
		BGTContractAddress: common.Address{},
		RewardVaultAddress: common.Address{},
		MinLiquidityStake:  big.NewInt(0),
		DelegationWeight:   big.NewInt(1),
		BlockReward:        new(big.Int).Div(new(big.Int).Mul(big.NewInt(2), big.NewInt(params.Ether)), big.NewInt(100)),
	}
}

// String implements the stringer interface
func (c *POAPOLConfig) String() string {
	period := uint64(0)
	epoch := uint64(0)
	if c.CliqueConfig != nil {
		period = c.CliqueConfig.Period
		epoch = c.CliqueConfig.Epoch
	}
	return fmt.Sprintf("poapol(period: %d, epoch: %d, bgtContract: %s, rewardVault: %s, minLiquidity: %s, delegationWeight: %s, blockReward: %s)",
		period, epoch, c.BGTContractAddress.Hex(), c.RewardVaultAddress.Hex(),
		c.MinLiquidityStake.String(), c.DelegationWeight.String(), c.BlockReward.String())
}

