# POA + POL Consensus Engine

Consensus engine kết hợp Proof-of-Authority (POA) và Proof-of-Liquidity (POL), lấy cảm hứng từ Berachain.

## Tổng Quan

Consensus engine này kết hợp:
- **POA (Proof-of-Authority)**: Hiệu quả và tốc độ cao với validators được ủy quyền
- **POL (Proof-of-Liquidity)**: Khuyến khích cung cấp thanh khoản thông qua BGT token và delegation

## Cấu Trúc

```
consensus/poapol/
├── consensus.go    # Main consensus engine
├── pol_state.go    # POL state management
├── config.go       # Configuration
└── README.md       # This file
```

## Sử Dụng

### 1. Tạo Config

```go
import (
    "github.com/ethereum/go-ethereum/consensus/poapol"
    "github.com/ethereum/go-ethereum/params"
)

cliqueConfig := &params.CliqueConfig{
    Period: 5,      // 5 seconds between blocks
    Epoch:  30000, // Reset votes every 30000 blocks
}

poapolConfig := poapol.NewPOAPOLConfig(cliqueConfig)
poapolConfig.BGTContractAddress = common.HexToAddress("0x...")
poapolConfig.RewardVaultAddress = common.HexToAddress("0x...")
poapolConfig.MinLiquidityStake = big.NewInt(1000000000000000000) // 1 token
poapolConfig.DelegationWeight = big.NewInt(1)
poapolConfig.BlockReward = new(big.Int).Div(new(big.Int).Mul(big.NewInt(2), big.NewInt(params.Ether)), big.NewInt(100))
```

### 2. Khởi Tạo Engine

```go
import (
    "github.com/ethereum/go-ethereum/consensus/poapol"
    "github.com/ethereum/go-ethereum/ethdb"
)

db := ... // Your database
engine := poapol.New(poapolConfig, db)
```

### 3. Sử Dụng Trong Node

Xem hướng dẫn chi tiết tại: `scripts/POA-POL-IMPLEMENTATION-GUIDE.md`

## Tính Năng

- ✅ POA consensus với validators được ủy quyền
- ✅ BGT token delegation tracking
- ✅ Liquidity stake management
- ✅ Reward distribution dựa trên BGT delegation
- ✅ Validator selection với weighted BGT delegation

## TODO

- [ ] Tích hợp với BGT smart contract
- [ ] Tích hợp với Reward Vault contract
- [ ] Implement weighted random validator selection
- [ ] Add slashing mechanism
- [ ] Performance optimization với caching
- [ ] Comprehensive testing

## Tài Liệu

Xem `scripts/POA-POL-IMPLEMENTATION-GUIDE.md` để biết hướng dẫn chi tiết về:
- Kiến trúc tổng quan
- Cách implement từng component
- Smart contracts cần thiết
- Testing và deployment

