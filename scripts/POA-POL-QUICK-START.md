# POA + POL Quick Start Guide

## 📦 Những Gì Đã Được Tạo

### 1. Core Consensus Engine
- ✅ `consensus/poapol/consensus.go` - Main POA-POL consensus engine
- ✅ `consensus/poapol/pol_state.go` - POL state management
- ✅ `consensus/poapol/config.go` - Configuration structure
- ✅ `consensus/poapol/README.md` - Documentation

### 2. Documentation
- ✅ `scripts/POA-POL-IMPLEMENTATION-GUIDE.md` - Hướng dẫn chi tiết đầy đủ
- ✅ `scripts/POA-POL-QUICK-START.md` - File này

## 🚀 Bước Tiếp Theo

### Bước 1: Deploy Smart Contracts

Bạn cần deploy 2 smart contracts chính:

1. **BGT Token Contract** (`contracts/BGTToken.sol`)
   - Non-transferable governance token
   - Quản lý delegation

2. **Reward Vault Contract** (`contracts/RewardVault.sol`)
   - Quản lý LP token staking
   - Phân phối BGT rewards

Xem code mẫu trong `scripts/POA-POL-IMPLEMENTATION-GUIDE.md`

### Bước 2: Cấu Hình Genesis Block

Tạo file `genesis.json`:

```json
{
  "config": {
    "chainId": 12345,
    "homesteadBlock": 0,
    "eip150Block": 0,
    "eip155Block": 0,
    "eip158Block": 0,
    "byzantiumBlock": 0,
    "constantinopleBlock": 0,
    "petersburgBlock": 0,
    "istanbulBlock": 0,
    "clique": {
      "period": 5,
      "epoch": 30000
    }
  },
  "alloc": {
    "0xYOUR_BGT_CONTRACT_ADDRESS": {
      "balance": "0"
    },
    "0xYOUR_REWARD_VAULT_ADDRESS": {
      "balance": "0"
    }
  },
  "extraData": "0x0000000000000000000000000000000000000000000000000000000000000000VALIDATOR1_ADDRESSVALIDATOR2_ADDRESS...0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
}
```

### Bước 3: Tích Hợp Vào Node

Cập nhật code khởi tạo node để sử dụng POAPOL engine:

```go
import (
    "github.com/ethereum/go-ethereum/consensus/poapol"
    "github.com/ethereum/go-ethereum/params"
    "github.com/ethereum/go-ethereum/common"
    "math/big"
)

func setupPOAPOLEngine(config *params.ChainConfig, db ethdb.Database) consensus.Engine {
    cliqueConfig := &params.CliqueConfig{
        Period: 5,
        Epoch:  30000,
    }
    
    poapolConfig := poapol.NewPOAPOLConfig(cliqueConfig)
    poapolConfig.BGTContractAddress = common.HexToAddress("0x...") // Your BGT contract
    poapolConfig.RewardVaultAddress = common.HexToAddress("0x...")  // Your Reward Vault
    poapolConfig.MinLiquidityStake = big.NewInt(1000000000000000000) // 1 token
    poapolConfig.DelegationWeight = big.NewInt(1)
    poapolConfig.BlockReward = new(big.Int).Div(
        new(big.Int).Mul(big.NewInt(2), big.NewInt(params.Ether)), 
        big.NewInt(100),
    )
    
    return poapol.New(poapolConfig, db)
}
```

### Bước 4: Khởi Động Node

```bash
# Init genesis
./geth --datadir ./data init genesis.json

# Start node
./geth --datadir ./data \
  --networkid 12345 \
  --http \
  --http.addr "0.0.0.0" \
  --http.port 8545 \
  --http.api "eth,net,web3,personal,miner" \
  --unlock "VALIDATOR_ADDRESS" \
  --password ./password.txt \
  --mine \
  --miner.etherbase "VALIDATOR_ADDRESS"
```

## 🔧 Customization

### 1. Điều Chỉnh Reward Formula

Sửa hàm `calculatePOLReward` trong `consensus/poapol/consensus.go`:

```go
func (p *POAPOL) calculatePOLReward(...) *big.Int {
    // Customize reward calculation here
    // Example: reward = baseReward * (1 + BGTDelegated / totalBGT)
}
```

### 2. Validator Selection Algorithm

Sửa hàm `SelectValidator` trong `consensus/poapol/pol_state.go`:

```go
func (ps *POLState) SelectValidator(...) (common.Address, error) {
    // Implement weighted random selection
    // or other selection algorithms
}
```

### 3. Tích Hợp Với Smart Contracts

Hiện tại, POL state được lưu trong state storage. Để tích hợp với smart contracts:

1. Thêm contract interaction trong `pol_state.go`
2. Sử dụng `vm.Call` để đọc từ BGT contract
3. Update state thông qua contract calls

## 📝 Workflow

### User Flow:

1. **Cung cấp thanh khoản** → Nhận LP tokens
2. **Stake LP tokens** vào Reward Vault → Nhận BGT
3. **Delegate BGT** cho validator
4. **Validator tạo block** → Nhận reward dựa trên BGT delegation

### Validator Flow:

1. **Stake native token** (tương tự POA)
2. **Nhận BGT delegation** từ users
3. **Tạo blocks** → Nhận reward
4. **Reward** = baseReward + bonus (dựa trên BGT delegation)

## ⚠️ Lưu Ý

1. **Smart Contracts**: Cần deploy và test kỹ trước khi mainnet
2. **Security**: Audit contracts và consensus logic
3. **Economic Model**: Cân bằng incentives để tránh centralization
4. **Performance**: Monitor và optimize state reads

## 📚 Tài Liệu

- Chi tiết đầy đủ: `scripts/POA-POL-IMPLEMENTATION-GUIDE.md`
- Code documentation: `consensus/poapol/README.md`
- Berachain docs: https://docs.berachain.com/

## 🐛 Troubleshooting

### Validator không nhận reward

- Kiểm tra BGT delegation đã được set chưa
- Verify reward calculation logic
- Check state storage slots

### Consensus không hoạt động

- Verify genesis config
- Check validator addresses trong extradata
- Ensure contracts đã được deploy

### Performance issues

- Implement caching cho validator info
- Optimize state reads
- Consider batch operations

## 🎯 Next Steps

1. ✅ Core consensus engine - DONE
2. ⏳ Deploy smart contracts
3. ⏳ Integrate với node
4. ⏳ Testing
5. ⏳ Security audit
6. ⏳ Mainnet deployment

