# Hướng Dẫn Setup Validator Node

## 📋 Tổng Quan

Hướng dẫn này sẽ giúp bạn chuẩn bị và vận hành một node làm validator trong mạng Ethereum private/testnet sử dụng Clique consensus (Proof-of-Authority).

---

## 🔧 Yêu Cầu Hệ Thống

### Phần Cứng Tối Thiểu

- **CPU**: 4+ cores
- **RAM**: 8GB
- **Storage**: 100GB+ (tùy thuộc vào chain size)
- **Network**: 8+ Mbps

### Phần Cứng Khuyến Nghị

- **CPU**: 8+ cores
- **RAM**: 16GB+
- **Storage**: SSD 500GB+
- **Network**: 25+ Mbps

### Phần Mềm

- **Go**: Version 1.23 hoặc mới hơn
- **C Compiler**: gcc hoặc clang
- **Git**: Để clone repository

---

## 📦 Bước 1: Build Geth Binary

```bash
# Clone repository (nếu chưa có)
cd /path/to/go-ethereum-custom

# Build geth
make geth

# Kiểm tra binary đã được build
./build/bin/geth version
```

---

## 🔐 Bước 2: Tạo Validator Account

### Option 1: Tạo Account Mới

```bash
# Tạo account mới
./build/bin/geth account new --datadir ~/validator-node

# Lưu lại:
# - Address (ví dụ: 0x36D84C24395ABC90006C3FF19292a54eDf591ac3)
# - Password (bạn sẽ nhập khi tạo)
```

### Option 2: Import Account Từ Private Key

```bash
# Tạo file chứa private key
echo "YOUR_PRIVATE_KEY" > /tmp/private_key.txt

# Tạo file password
echo "YOUR_PASSWORD" > /tmp/password.txt

# Import account
./build/bin/geth account import \
  --datadir ~/validator-node \
  --password /tmp/password.txt \
  /tmp/private_key.txt

# Xóa file tạm
rm /tmp/private_key.txt /tmp/password.txt
```

**Lưu ý**: Lưu lại validator address và password để sử dụng sau.

---

## 📄 Bước 3: Tạo Genesis File

Tạo file `genesis.json` với cấu hình Clique consensus:

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

### Giải Thích Các Tham Số:

- **chainId**: ID của chain (1337 cho testnet)
- **clique.period**: Thời gian giữa các block (giây) - 5 = 5 giây
- **clique.epoch**: Số block giữa các epoch (30000)
- **extradata**: Chứa validator addresses (mỗi address 20 bytes, padding với 0x00)
- **alloc**: Pre-fund accounts trong genesis

### Cách Tạo extradata:

```bash
# extradata format:
# 0x + 32 bytes (0x00) + validator1 (20 bytes) + validator2 (20 bytes) + ... + 32 bytes (0x00)

# Ví dụ với 2 validators:
# 0x0000000000000000000000000000000000000000000000000000000000000000
# 36d84c24395abc90006c3ff19292a54edf591ac3
# b49433628173fc5b51bf3af6b7f96c8efc1626ec
# 0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
```

---

## 🚀 Bước 4: Initialize Blockchain

```bash
# Initialize blockchain với genesis file
./build/bin/geth init --datadir ~/validator-node genesis.json

# Kiểm tra đã init thành công
ls ~/validator-node/geth/
```

---

## ⚙️ Bước 5: Tạo Config File (Optional)

Tạo file `config.toml` để cấu hình node:

```toml
[Node]
DataDir = "~/validator-node"

[Eth]
NetworkId = 1337
SyncMode = "full"

[Node.P2P]
MaxPeers = 50
NoDiscovery = false
StaticNodes = [
    "enode://NODE1_ENODE@IP:PORT",
    "enode://NODE2_ENODE@IP:PORT"
]

[Node.HTTP]
Host = "0.0.0.0"
Port = 8545
APIs = ["eth", "net", "web3", "miner", "admin"]

[Node.WS]
Host = "0.0.0.0"
Port = 8546
APIs = ["eth", "net", "web3", "miner", "admin"]

[Node.Auth]
Addr = "0.0.0.0"
Port = 8551
```

---

## 🎯 Bước 6: Start Validator Node

### Cách 1: Sử dụng Command Line Flags

```bash
./build/bin/geth \
  --datadir ~/validator-node \
  --networkid 1337 \
  --port 30303 \
  --http \
  --http.addr "0.0.0.0" \
  --http.port 8545 \
  --http.api "eth,net,web3,miner,admin" \
  --ws \
  --ws.addr "0.0.0.0" \
  --ws.port 8546 \
  --ws.api "eth,net,web3,miner,admin" \
  --authrpc.addr "0.0.0.0" \
  --authrpc.port 8551 \
  --unlock "VALIDATOR_ADDRESS" \
  --password /path/to/password.txt \
  --allow-insecure-unlock \
  --maxpeers 50 \
  --cache 1024 \
  --cache.database 50 \
  --cache.trie 15 \
  --cache.gc 25 \
  --cache.snapshot 10 \
  --txpool.globalslots 4096 \
  --txpool.globalqueue 1024 \
  console
```

### Cách 2: Sử dụng Config File

```bash
./build/bin/geth --config config.toml \
  --unlock "VALIDATOR_ADDRESS" \
  --password /path/to/password.txt \
  --allow-insecure-unlock \
  console
```

### Các Flags Quan Trọng:

- `--datadir`: Thư mục chứa blockchain data
- `--networkid`: Network ID (phải khớp với genesis)
- `--unlock`: Unlock validator account để sign blocks
- `--password`: File chứa password (hoặc dùng `--password` với stdin)
- `--allow-insecure-unlock`: Cho phép unlock qua HTTP (chỉ dùng cho testnet)
- `--http.api`: APIs exposed qua HTTP
- `--ws.api`: APIs exposed qua WebSocket
- `--maxpeers`: Số lượng peers tối đa
- `--cache`: Cache size (MB)

---

## 🔓 Bước 7: Unlock Validator Account

### Nếu chưa unlock khi start:

```bash
# Attach vào node console
./build/bin/geth attach ~/validator-node/geth.ipc

# Hoặc qua HTTP
./build/bin/geth attach http://localhost:8545
```

Trong console:

```javascript
// Unlock account (0 = unlock forever)
personal.unlockAccount("VALIDATOR_ADDRESS", "PASSWORD", 0);

// Kiểm tra account đã unlock
eth.accounts;

// Set coinbase (validator address)
miner.setEtherbase("VALIDATOR_ADDRESS");

// Kiểm tra coinbase
eth.coinbase;
```

---

## ✅ Bước 8: Kiểm Tra Validator Hoạt Động

### Trong Geth Console:

```javascript
// Kiểm tra block number
eth.blockNumber;

// Kiểm tra peers
admin.peers.length;
admin.peers;

// Kiểm tra node info
admin.nodeInfo;

// Kiểm tra coinbase (validator address)
eth.coinbase;

// Kiểm tra balance
eth.getBalance(eth.coinbase);

// Kiểm tra block mới nhất
eth.getBlock("latest");
```

### Kiểm Tra Block Production:

```bash
# Watch block number
watch -n 1 './build/bin/geth attach --exec "eth.blockNumber" ~/validator-node/geth.ipc'

# Hoặc dùng script
./build/bin/geth attach --exec "eth.blockNumber" ~/validator-node/geth.ipc
```

---

## 🔗 Bước 9: Kết Nối Với Peers

### Lấy Enode của Node:

```javascript
// Trong geth console
admin.nodeInfo.enode;
```

### Kết Nối Với Peer Khác:

```javascript
// Trong geth console
admin.addPeer("enode://PEER_ENODE@IP:PORT");

// Kiểm tra peers
admin.peers;
```

### Hoặc Thêm Vào Config:

```toml
[Node.P2P]
StaticNodes = [
    "enode://PEER1_ENODE@IP1:PORT1",
    "enode://PEER2_ENODE@IP2:PORT2"
]
```

---

## 🛠️ Troubleshooting

### 1. Validator Không Tạo Block

**Nguyên nhân:**

- Account chưa được unlock
- Validator address không có trong genesis extradata
- Không có peers để sync

**Giải pháp:**

```javascript
// Unlock account
personal.unlockAccount("VALIDATOR_ADDRESS", "PASSWORD", 0);

// Set coinbase
miner.setEtherbase("VALIDATOR_ADDRESS");

// Kiểm tra trong genesis
// Validator address phải có trong extradata
```

### 2. Node Không Kết Nối Với Peers

**Nguyên nhân:**

- Firewall chặn port
- Network ID không khớp
- Genesis hash không khớp

**Giải pháp:**

```bash
# Kiểm tra firewall
sudo ufw status
sudo ufw allow 30303/tcp
sudo ufw allow 30303/udp

# Kiểm tra network ID
./build/bin/geth attach --exec "net.version" ~/validator-node/geth.ipc

# Kiểm tra genesis hash
./build/bin/geth attach --exec "eth.getBlock(0).hash" ~/validator-node/geth.ipc
```

### 3. Block Production Chậm

**Nguyên nhân:**

- Cache quá nhỏ
- Disk I/O chậm
- CPU không đủ mạnh

**Giải pháp:**

```bash
# Tăng cache
--cache 2048 --cache.database 100 --cache.trie 30

# Sử dụng SSD
# Tăng CPU cores
```

### 4. Account Locked Sau Khi Restart

**Giải pháp:**

- Sử dụng `--unlock` flag khi start
- Hoặc unlock lại sau khi start
- Hoặc sử dụng password file với `--password`

---

## 📊 Monitoring

### Script Kiểm Tra Status:

```bash
#!/bin/bash
# check-validator.sh

DATADIR=~/validator-node

echo "Block Number: $(./build/bin/geth attach --exec 'eth.blockNumber' $DATADIR/geth.ipc)"
echo "Peers: $(./build/bin/geth attach --exec 'admin.peers.length' $DATADIR/geth.ipc)"
echo "Coinbase: $(./build/bin/geth attach --exec 'eth.coinbase' $DATADIR/geth.ipc)"
echo "Balance: $(./build/bin/geth attach --exec 'web3.fromWei(eth.getBalance(eth.coinbase), \"ether\")' $DATADIR/geth.ipc) ETH"
```

---

## 🔒 Security Best Practices

### 1. Bảo Mật Private Key

- **KHÔNG** commit private key vào git
- **KHÔNG** share private key
- Sử dụng hardware wallet cho production
- Encrypt password file

### 2. Network Security

- Chỉ expose RPC cho localhost trong production
- Sử dụng firewall
- Sử dụng reverse proxy (nginx) với authentication
- Enable HTTPS cho RPC

### 3. Account Management

- Sử dụng strong password
- Backup keystore files
- Không unlock account với `--allow-insecure-unlock` trong production

---

## 📝 Checklist Setup Validator

- [ ] Build geth binary thành công
- [ ] Tạo/import validator account
- [ ] Lưu validator address và password
- [ ] Tạo genesis file với validator trong extradata
- [ ] Initialize blockchain với genesis
- [ ] Tạo config file (optional)
- [ ] Start node với đúng flags
- [ ] Unlock validator account
- [ ] Set coinbase
- [ ] Kết nối với peers
- [ ] Kiểm tra block production
- [ ] Setup monitoring
- [ ] Backup keystore files

---

## 🎯 Quick Start Script

Tạo script `start-validator.sh`:

```bash
#!/bin/bash

DATADIR=~/validator-node
VALIDATOR_ADDRESS="YOUR_VALIDATOR_ADDRESS"
PASSWORD_FILE="/path/to/password.txt"
GENESIS_FILE="genesis.json"
NETWORKID=1337

# Build geth if not exists
if [ ! -f "./build/bin/geth" ]; then
    echo "Building geth..."
    make geth
fi

# Initialize if not exists
if [ ! -d "$DATADIR/geth" ]; then
    echo "Initializing blockchain..."
    ./build/bin/geth init --datadir "$DATADIR" "$GENESIS_FILE"
fi

# Start node
./build/bin/geth \
  --datadir "$DATADIR" \
  --networkid "$NETWORKID" \
  --port 30303 \
  --http --http.addr "0.0.0.0" --http.port 8545 \
  --http.api "eth,net,web3,miner,admin" \
  --ws --ws.addr "0.0.0.0" --ws.port 8546 \
  --ws.api "eth,net,web3,miner,admin" \
  --authrpc.addr "0.0.0.0" --authrpc.port 8551 \
  --unlock "$VALIDATOR_ADDRESS" \
  --password "$PASSWORD_FILE" \
  --allow-insecure-unlock \
  --maxpeers 50 \
  --cache 1024 \
  console
```

---

## 📚 Tài Liệu Tham Khảo

- [Geth Documentation](https://geth.ethereum.org/docs)
- [Clique Consensus](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-225.md)
- [Genesis Configuration](https://geth.ethereum.org/docs/interface/genesis)
- [Command Line Options](https://geth.ethereum.org/docs/fundamentals/command-line-options)

---

## 💡 Tips

1. **Test trên testnet trước** khi chạy production
2. **Monitor logs** để phát hiện vấn đề sớm
3. **Backup thường xuyên** keystore và data directory
4. **Sử dụng systemd** để auto-restart node
5. **Setup alerts** cho block production stops
6. **Document** tất cả các thay đổi config

---

**Chúc bạn setup validator thành công! 🚀**
