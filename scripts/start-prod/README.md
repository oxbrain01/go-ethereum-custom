# Custom Blockchain Setup

Script này tạo và chạy một blockchain Ethereum mới từ đầu, không kết nối với mainnet.

## 📋 Thông tin Blockchain

- **Chain ID**: 2026
- **Network ID**: 2026
- **Consensus**: Proof of Authority (POA - Clique)
- **Block Period**: 5 seconds
- **Epoch**: 30000 blocks
- **Gas Limit**: 30,000,000
- **Base Fee**: 1 Gwei

## 🚀 Cách sử dụng

### 1. Start Blockchain

```bash
./scripts/start-prod/start-prod.sh
```

Script sẽ:

- Tự động tạo genesis block nếu chưa có
- Start node với tất cả tính năng Ethereum
- Enable tất cả APIs (HTTP, WebSocket, GraphQL, Engine)

### 2. Kết nối với Node

**HTTP RPC**: `http://localhost:8545`
**WebSocket**: `ws://localhost:8546`
**GraphQL**: `http://localhost:8545/graphql`
**Engine API**: `http://localhost:8551`

## 💰 Pre-funded Accounts

Genesis block đã pre-fund 5 accounts với 1,000,000 ETH mỗi account:

1. `0x356981ee849c96fC40e78B0B22715345E57746fb` - 1,000,000 ETH
2. `0x3bE69C0DEf08196BEE31D463741Df2B92D3eaf8E` - 1,000,000 ETH
3. `0xC4fa658C3C835b316CaCB52338eD9ebbce2631D7` - 1,000,000 ETH
4. `0x1120CFB327baedC2f2638D75Db0935b7f3CC934b` - 1,000,000 ETH
5. `0x554bdA38d6635155b06Faa43189B52D9eD579f70` - 1,000,000 ETH

**Lưu ý**: Đây là các addresses mẫu. Bạn có thể tạo accounts mới và thêm vào genesis.json.

## 🔧 Tính năng đã bật

### APIs

- ✅ `eth` - Ethereum JSON-RPC API
- ✅ `net` - Network API
- ✅ `web3` - Web3 API
- ✅ `engine` - Engine API (cho validators)
- ✅ `admin` - Admin API
- ✅ `debug` - Debug API
- ✅ `txpool` - Transaction Pool API
- ✅ `miner` - Miner API
- ✅ `graphql` - GraphQL API

### Ethereum Features

- ✅ Tất cả hard forks enabled từ genesis
- ✅ EIP-1559 (Dynamic gas pricing)
- ✅ EIP-4844 (Blob transactions - 6 blobs/block)
- ✅ Full state history
- ✅ State pruning (optimized storage)

### Network

- ✅ Private network (no discovery)
- ✅ Standalone blockchain
- ✅ Ready for multi-node setup

## 📝 Tùy chỉnh

### Thay đổi Genesis Block

Chỉnh sửa `genesis.json`:

- Thay đổi `chainId` và `NetworkId` trong config.toml
- Thêm/bớt accounts trong `alloc`
- Điều chỉnh `gasLimit`, `baseFeePerGas`

Sau đó xóa thư mục `data/` và chạy lại script để init lại.

### Thêm Accounts mới

1. Tạo account mới:

```bash
./build/bin/geth --datadir ./scripts/start-prod/data account new
```

2. Thêm vào `genesis.json` trong phần `alloc`:

```json
"0xYOUR_ADDRESS": {
  "balance": "1000000000000000000000000"
}
```

3. Xóa `data/` và init lại genesis.

## 🧹 Cleanup & Reset

### Reset Blockchain (Xóa và init lại)

Nếu bạn thay đổi chain ID hoặc genesis block, cần reset blockchain:

```bash
# Cách 1: Sử dụng script reset
./scripts/start-prod/reset-chain.sh

# Cách 2: Xóa thủ công
rm -rf scripts/start-prod/data/
```

Sau đó chạy lại script để init genesis block mới:

```bash
./scripts/start-prod/start-prod.sh
```

### Lỗi "RPC does not match the chainID"

Nếu wallet (như Rabby) báo lỗi "RPC does not match the chainID", có thể do:

1. Database cũ vẫn còn với chain ID cũ
2. Node chưa được init lại với genesis block mới

**Giải pháp:**

```bash
# 1. Dừng node nếu đang chạy (Ctrl+C)
# 2. Reset blockchain
./scripts/start-prod/reset-chain.sh
# 3. Start lại
./scripts/start-prod/start-prod.sh
# 4. Kiểm tra chain ID
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
  http://localhost:8545
# Kết quả phải là: {"jsonrpc":"2.0","id":1,"result":"0x7ea"} (2026 trong hex)
```

## 🔗 Kết nối nhiều nodes

Để kết nối nhiều nodes với nhau:

1. Start node đầu tiên (node này sẽ mining)
2. Lấy enode của node đầu tiên:

```bash
# Trong geth console
admin.nodeInfo.enode
```

3. Thêm vào `config.toml` của node thứ 2:

```toml
[Node.P2P]
StaticNodes = ["enode://..."]
```

4. Start node thứ 2 với cùng genesis.json

## 💸 Transfer Balance Script

A convenient script is available to transfer balance between wallets for testing:

```bash
# Transfer 0.1 ETH from default account 1 to account 2
./scripts/start-prod/transfer-balance.sh

# Transfer 1.5 ETH between specific accounts
./scripts/start-prod/transfer-balance.sh 0x3569... 0x3bE6... 1.5

# Transfer with default amount (0.1 ETH)
./scripts/start-prod/transfer-balance.sh 0x3569... 0x3bE6...

# Get help
./scripts/start-prod/transfer-balance.sh --help
```

**Note**: The script uses `eth_sendTransaction` which requires the account to be unlocked. The validator account is automatically unlocked in `start-prod.sh`.

## 📚 Tài liệu thêm

- [Geth Documentation](https://geth.ethereum.org/docs)
- [Ethereum JSON-RPC API](https://ethereum.org/en/developers/docs/apis/json-rpc/)
- [Genesis Block Format](https://geth.ethereum.org/docs/interface/private-network)
