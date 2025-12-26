// Copyright 2025 InsChain Foundation

package types

import (
	"bytes"
	"errors"
	"math/big"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/params"
	"github.com/ethereum/go-ethereum/rlp"
)

type PoLTx struct {
	ChainID    *big.Int
	Nonce      uint64
	GasLimit  uint64
	GasPrice  *big.Int
	From       common.Address
	To         common.Address
	Data       []byte
}

var _ TxData = (*PoLTx)(nil)

var (
	bytesType, _ = abi.NewType("bytes", "", nil)
	distributeForMethod = abi.NewMethod(
		"distributeFor",
		"distributeFor",
		abi.Function,
		"nonpayable",
		false,
		false,
		[]abi.Argument{
			{
				Name: "pubkey",
				Type: bytesType,
				Indexed: false,
			},
		},
		nil,
	)
)

func (tx *PoLTx) copy() TxData {
	cpy := &PoLTx{
		ChainID: new(big.Int),
		Nonce: tx.Nonce,
		GasLimit: tx.GasLimit,
		GasPrice: new(big.Int),
		From: tx.From,
		To: tx.To,
		Data: common.CopyBytes(tx.Data),
	}
	if tx.ChainID != nil {
		cpy.ChainID.Set(tx.ChainID)
	}
	
	if tx.GasPrice != nil {
		cpy.GasPrice.Set(tx.GasPrice)
	}

	return cpy
}

func (tx *PoLTx) chainID() *big.Int {
	return tx.ChainID
}

func (*PoLTx) accessList() AccessList {
	return nil
}

func (tx *PoLTx) data() []byte {
	return tx.Data
}

func (tx *PoLTx) gas() uint64 {
	return tx.GasLimit
}

func (tx *PoLTx) gasPrice() *big.Int {
	return tx.GasPrice
}

func (tx *PoLTx) gasTipCap() *big.Int {
	return common.Big0
}

func (tx *PoLTx) gasFeeCap() *big.Int {
	return tx.GasPrice
}

func ( *PoLTx) value() *big.Int {
	return common.Big0
}

func (tx *PoLTx) nonce() uint64 {
	return tx.Nonce
}

func (tx *PoLTx) to() *common.Address {
	return &tx.To
}

func ( *PoLTx) txType() byte {
	return PoLTxType
}

func (*PoLTx) rawSignatureValues() (v, r, s *big.Int) {
	return common.Big0, common.Big0, common.Big0
}

func ( *PoLTx) setSignatureValues(chainID, v, r, s *big.Int) {

}

func (tx *PoLTx) effectiveGasPrice(dst *big.Int, baseFee *big.Int) *big.Int {
	return dst.Set(tx.GasPrice)
}

func (tx *PoLTx) encode(b *bytes.Buffer) error {
	return rlp.Encode(b, tx)
}

func (tx *PoLTx) decode(input []byte) error {
	return rlp.DecodeBytes(input, tx)
}

func (tx *PoLTx) sigHash(chainID *big.Int) common.Hash {
	return prefixedRlpHash(
		PoLTxType,
		[]any{
			chainID,
			tx.From,
			tx.To,
			tx.Nonce,
			tx.GasPrice,
			tx.GasLimit,
			tx.Data,
		})
}

func NewPoLTx(
	chainID *big.Int,
	distributorAddress common.Address,
	currentBlockNumber *big.Int,
	gasLimit uint64,
	baseFee *big.Int,
	pubkey *common.Pubkey,
)(*Transaction, error){
	data, err := getDistributeForData(pubkey)

	if err != nil {
		return nil, err
	}

	if currentBlockNumber.Sign() <= 0 {
		return nil, errors.New("currentBlockNumber is less than 0. Must be greater than 0")
	}

	return NewTx(&PoLTx{
		ChainID:    chainID,
		Nonce:      currentBlockNumber.Uint64() - 1,
		GasLimit:   gasLimit,
		GasPrice:   baseFee,
		From:       params.SystemAddress,
		To:         distributorAddress,
		Data:       data,
	}), nil


}

func getDistributeForData(pubkey *common.Pubkey) ([]byte, error){
	if pubkey == nil {
		return nil, errors.New("pubkey is nil")
	}

	arguments, err := distributeForMethod.Inputs.Pack(pubkey.Bytes())
	if err != nil {
		return nil, err
	}
	return append(distributeForMethod.ID, arguments...), nil
}

func IsPoLDistribution(from common.Address, to *common.Address, data []byte, distributorAddress common.Address) bool {
	return from == params.SystemAddress && to != nil && *to == distributorAddress && isDistributeForCall(data)
}

func isDistributeForCall(data []byte) bool {
	if len(data) < 4{
		return false
	}
	return bytes.Equal(data[:4], distributeForMethod.ID)
}