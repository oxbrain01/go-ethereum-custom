# Cách Lấy Danh Sách Mempool - Hướng Dẫn Chi Tiết

## 📋 Tổng Quan

Có nhiều cách để lấy danh sách transactions trong mempool từ Geth node. Tài liệu này sẽ hướng dẫn tất cả các phương pháp.

---

## 🔌 Các RPC Methods

### 1. `txpool_status` - Lấy Số Lượng Transactions

**Mục đích:** Lấy số lượng transactions hiện tại trong mempool (pending và queued)

**RPC Call:**
```json
{
  "jsonrpc": "2.0",
  "method": "txpool_status",
  "params": [],
  "id": 1
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "pending": "0x5",    // 5 pending transactions
    "queued": "0x2"      // 2 queued transactions
  }
}
```

**Code Implementation:**
```javascript
async function getMempoolStatus() {
  const response = await fetch('http://localhost:8546', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      method: 'txpool_status',
      params: [],
      id: 1
    })
  });
  
  const data = await response.json();
  return {
    pending: parseInt(data.result.pending, 16),
    queued: parseInt(data.result.queued, 16)
  };
}
```

**Go Code:** `internal/ethapi/api.go:239`
```go
func (api *TxPoolAPI) Status() map[string]hexutil.Uint {
    pending, queue := api.b.Stats()
    return map[string]hexutil.Uint{
        "pending": hexutil.Uint(pending),
        "queued":  hexutil.Uint(queue),
    }
}
```

---

### 2. `txpool_content` - Lấy Toàn Bộ Transactions

**Mục đích:** Lấy tất cả transactions trong mempool, nhóm theo account và nonce

**RPC Call:**
```json
{
  "jsonrpc": "2.0",
  "method": "txpool_content",
  "params": [],
  "id": 1
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "pending": {
      "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb": {
        "5": {
          "blockHash": null,
          "blockNumber": null,
          "from": "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb",
          "gas": "0x5208",
          "gasPrice": "0x4a817c800",
          "hash": "0x...",
          "input": "0x",
          "nonce": "0x5",
          "to": "0x...",
          "transactionIndex": null,
          "value": "0x2386f26fc10000"
        }
      }
    },
    "queued": {
      "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb": {
        "10": {
          // ... transaction details
        }
      }
    }
  }
}
```

**Cấu trúc Response:**
```
{
  "pending": {
    "0xAddress1": {
      "nonce1": { transaction object },
      "nonce2": { transaction object }
    },
    "0xAddress2": {
      "nonce1": { transaction object }
    }
  },
  "queued": {
    // Tương tự pending
  }
}
```

**Code Implementation:**
```javascript
async function getMempoolContent() {
  const response = await fetch('http://localhost:8546', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      method: 'txpool_content',
      params: [],
      id: 1
    })
  });
  
  const data = await response.json();
  return data.result; // { pending: {...}, queued: {...} }
}

// Flatten thành array
function flattenMempoolContent(content) {
  const allTxs = [];
  
  // Pending transactions
  for (const [address, txs] of Object.entries(content.pending || {})) {
    for (const [nonce, tx] of Object.entries(txs)) {
      allTxs.push({
        ...tx,
        address,
        nonce: parseInt(nonce),
        status: 'pending'
      });
    }
  }
  
  // Queued transactions
  for (const [address, txs] of Object.entries(content.queued || {})) {
    for (const [nonce, tx] of Object.entries(txs)) {
      allTxs.push({
        ...tx,
        address,
        nonce: parseInt(nonce),
        status: 'queued'
      });
    }
  }
  
  return allTxs;
}
```

**Go Code:** `internal/ethapi/api.go:189`
```go
func (api *TxPoolAPI) Content() map[string]map[string]map[string]*RPCTransaction {
    pending, queue := api.b.TxPoolContent()
    content := map[string]map[string]map[string]*RPCTransaction{
        "pending": make(map[string]map[string]*RPCTransaction, len(pending)),
        "queued":  make(map[string]map[string]*RPCTransaction, len(queue)),
    }
    curHeader := api.b.CurrentHeader()
    
    // Flatten pending transactions
    for account, txs := range pending {
        dump := make(map[string]*RPCTransaction, len(txs))
        for _, tx := range txs {
            dump[fmt.Sprintf("%d", tx.Nonce())] = NewRPCPendingTransaction(tx, curHeader, api.b.ChainConfig())
        }
        content["pending"][account.Hex()] = dump
    }
    
    // Flatten queued transactions
    for account, txs := range queue {
        dump := make(map[string]*RPCTransaction, len(txs))
        for _, tx := range txs {
            dump[fmt.Sprintf("%d", tx.Nonce())] = NewRPCPendingTransaction(tx, curHeader, api.b.ChainConfig())
        }
        content["queued"][account.Hex()] = dump
    }
    
    return content
}
```

---

### 3. `txpool_contentFrom` - Lấy Transactions của Một Address

**Mục đích:** Lấy transactions của một address cụ thể trong mempool

**RPC Call:**
```json
{
  "jsonrpc": "2.0",
  "method": "txpool_contentFrom",
  "params": ["0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb"],
  "id": 1
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "pending": {
      "5": { /* transaction */ },
      "6": { /* transaction */ }
    },
    "queued": {
      "10": { /* transaction */ }
    }
  }
}
```

**Code Implementation:**
```javascript
async function getMempoolContentFrom(address) {
  const response = await fetch('http://localhost:8546', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      method: 'txpool_contentFrom',
      params: [address],
      id: 1
    })
  });
  
  const data = await response.json();
  return data.result;
}
```

**Go Code:** `internal/ethapi/api.go:216`
```go
func (api *TxPoolAPI) ContentFrom(addr common.Address) map[string]map[string]*RPCTransaction {
    content := make(map[string]map[string]*RPCTransaction, 2)
    pending, queue := api.b.TxPoolContentFrom(addr)
    curHeader := api.b.CurrentHeader()
    
    // Build pending transactions
    dump := make(map[string]*RPCTransaction, len(pending))
    for _, tx := range pending {
        dump[fmt.Sprintf("%d", tx.Nonce())] = NewRPCPendingTransaction(tx, curHeader, api.b.ChainConfig())
    }
    content["pending"] = dump
    
    // Build queued transactions
    dump = make(map[string]*RPCTransaction, len(queue))
    for _, tx := range queue {
        dump[fmt.Sprintf("%d", tx.Nonce())] = NewRPCPendingTransaction(tx, curHeader, api.b.ChainConfig())
    }
    content["queued"] = dump
    
    return content
}
```

---

### 4. `txpool_inspect` - Lấy Thông Tin Tóm Tắt

**Mục đích:** Lấy thông tin tóm tắt của transactions (dạng string, dễ đọc)

**RPC Call:**
```json
{
  "jsonrpc": "2.0",
  "method": "txpool_inspect",
  "params": [],
  "id": 1
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "pending": {
      "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb": {
        "5": "0x...: 10000000000000000 wei + 21000 gas × 20000000000 wei"
      }
    },
    "queued": {}
  }
}
```

**Format String:** `"to_address: value wei + gas × gasPrice wei"`

**Code Implementation:**
```javascript
async function getMempoolInspect() {
  const response = await fetch('http://localhost:8546', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      method: 'txpool_inspect',
      params: [],
      id: 1
    })
  });
  
  const data = await response.json();
  return data.result;
}
```

**Go Code:** `internal/ethapi/api.go:248`
```go
func (api *TxPoolAPI) Inspect() map[string]map[string]map[string]string {
    pending, queue := api.b.TxPoolContent()
    content := map[string]map[string]map[string]string{
        "pending": make(map[string]map[string]string, len(pending)),
        "queued":  make(map[string]map[string]string, len(queue)),
    }
    
    // Format transaction as string
    format := func(tx *types.Transaction) string {
        if to := tx.To(); to != nil {
            return fmt.Sprintf("%s: %v wei + %v gas × %v wei", 
                tx.To().Hex(), tx.Value(), tx.Gas(), tx.GasPrice())
        }
        return fmt.Sprintf("contract creation: %v wei + %v gas × %v wei", 
            tx.Value(), tx.Gas(), tx.GasPrice())
    }
    
    // Flatten pending
    for account, txs := range pending {
        dump := make(map[string]string, len(txs))
        for _, tx := range txs {
            dump[fmt.Sprintf("%d", tx.Nonce())] = format(tx)
        }
        content["pending"][account.Hex()] = dump
    }
    
    // Flatten queued
    for account, txs := range queue {
        dump := make(map[string]string, len(txs))
        for _, tx := range txs {
            dump[fmt.Sprintf("%d", tx.Nonce())] = format(tx)
        }
        content["queued"][account.Hex()] = dump
    }
    
    return content
}
```

---

### 5. `eth_pendingTransactions` - Lấy Pending Transactions (Local Accounts)

**Mục đích:** Lấy pending transactions từ các accounts được quản lý bởi node này

**Lưu ý:** Chỉ trả về transactions từ local accounts (accounts trong keystore của node)

**RPC Call:**
```json
{
  "jsonrpc": "2.0",
  "method": "eth_pendingTransactions",
  "params": [],
  "id": 1
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": [
    {
      "blockHash": null,
      "blockNumber": null,
      "from": "0x...",
      "gas": "0x5208",
      "gasPrice": "0x4a817c800",
      "hash": "0x...",
      "input": "0x",
      "nonce": "0x5",
      "to": "0x...",
      "transactionIndex": null,
      "value": "0x2386f26fc10000"
    }
  ]
}
```

**Code Implementation:**
```javascript
async function getPendingTransactions() {
  const response = await fetch('http://localhost:8546', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      method: 'eth_pendingTransactions',
      params: [],
      id: 1
    })
  });
  
  const data = await response.json();
  return data.result; // Array of transactions
}
```

**Go Code:** `internal/ethapi/api.go:1851`
```go
func (api *TransactionAPI) PendingTransactions() ([]*RPCTransaction, error) {
    pending, err := api.b.GetPoolTransactions()
    if err != nil {
        return nil, err
    }
    
    // Get local accounts
    accounts := make(map[common.Address]struct{})
    for _, wallet := range api.b.AccountManager().Wallets() {
        for _, account := range wallet.Accounts() {
            accounts[account.Address] = struct{}{}
        }
    }
    
    curHeader := api.b.CurrentHeader()
    transactions := make([]*RPCTransaction, 0, len(pending))
    
    // Filter only local account transactions
    for _, tx := range pending {
        from, _ := types.Sender(api.signer, tx)
        if _, exists := accounts[from]; exists {
            transactions = append(transactions, 
                NewRPCPendingTransaction(tx, curHeader, api.b.ChainConfig()))
        }
    }
    
    return transactions, nil
}
```

---

## 📡 WebSocket Subscription - Real-time Monitoring

### `eth_subscribe` - Subscribe New Pending Transactions

**Mục đích:** Nhận notification ngay lập tức khi có transaction mới vào mempool

**WebSocket Call:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "eth_subscribe",
  "params": ["newPendingTransactions"]
}
```

**Response (Subscription Confirmation):**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": "0x123abc..."  // Subscription ID
}
```

**Notification (Khi có transaction mới):**
```json
{
  "jsonrpc": "2.0",
  "method": "eth_subscription",
  "params": {
    "subscription": "0x123abc...",
    "result": "0xtxhash..."  // Transaction hash
  }
}
```

**Code Implementation:**
```javascript
const WebSocket = require('ws');

const ws = new WebSocket('ws://localhost:8547');

ws.on('open', () => {
  // Subscribe to new pending transactions
  ws.send(JSON.stringify({
    jsonrpc: '2.0',
    id: 1,
    method: 'eth_subscribe',
    params: ['newPendingTransactions']
  }));
});

ws.on('message', (data) => {
  const message = JSON.parse(data.toString());
  
  // Subscription confirmation
  if (message.result && typeof message.result === 'string') {
    console.log('Subscribed:', message.result);
    return;
  }
  
  // Transaction notification
  if (message.params && message.params.result) {
    const txHash = message.params.result;
    console.log('New transaction:', txHash);
    
    // Query full transaction details
    getTransactionByHash(txHash).then(tx => {
      console.log('Transaction details:', tx);
    });
  }
});

async function getTransactionByHash(hash) {
  const response = await fetch('http://localhost:8546', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      method: 'eth_getTransactionByHash',
      params: [hash],
      id: 1
    })
  });
  
  const data = await response.json();
  return data.result;
}
```

**Subscribe với Full Transaction:**
```javascript
// Subscribe và nhận full transaction object thay vì chỉ hash
ws.send(JSON.stringify({
  jsonrpc: '2.0',
  id: 1,
  method: 'eth_subscribe',
  params: ['newPendingTransactions', true]  // true = full transaction
}));
```

---

## 🔧 Ví Dụ Hoàn Chỉnh

### Example 1: Lấy Tất Cả Transactions và Đếm

```javascript
async function getAllMempoolTransactions() {
  // 1. Lấy status
  const status = await getMempoolStatus();
  console.log(`Pending: ${status.pending}, Queued: ${status.queued}`);
  
  // 2. Lấy content
  const content = await getMempoolContent();
  
  // 3. Flatten thành array
  const allTxs = flattenMempoolContent(content);
  
  console.log(`Total transactions: ${allTxs.length}`);
  console.log(`Pending: ${allTxs.filter(tx => tx.status === 'pending').length}`);
  console.log(`Queued: ${allTxs.filter(tx => tx.status === 'queued').length}`);
  
  return allTxs;
}
```

### Example 2: Monitor Mempool Real-time

```javascript
const WebSocket = require('ws');

class MempoolMonitor {
  constructor(rpcUrl, wsUrl) {
    this.rpcUrl = rpcUrl;
    this.wsUrl = wsUrl;
    this.ws = null;
    this.transactions = new Map();
  }
  
  async start() {
    // Connect WebSocket
    this.ws = new WebSocket(this.wsUrl);
    
    this.ws.on('open', () => {
      console.log('Connected to WebSocket');
      
      // Subscribe
      this.ws.send(JSON.stringify({
        jsonrpc: '2.0',
        id: 1,
        method: 'eth_subscribe',
        params: ['newPendingTransactions']
      }));
    });
    
    this.ws.on('message', async (data) => {
      const message = JSON.parse(data.toString());
      
      if (message.params && message.params.result) {
        const txHash = message.params.result;
        await this.handleNewTransaction(txHash);
      }
    });
    
    // Periodically sync với mempool content
    setInterval(() => this.syncMempool(), 5000);
  }
  
  async handleNewTransaction(txHash) {
    // Get transaction details
    const tx = await this.getTransaction(txHash);
    if (tx) {
      this.transactions.set(txHash, tx);
      console.log('New transaction:', {
        hash: txHash,
        from: tx.from,
        to: tx.to,
        value: tx.value,
        gasPrice: tx.gasPrice
      });
    }
  }
  
  async syncMempool() {
    // Lấy toàn bộ mempool để sync
    const content = await this.getMempoolContent();
    const allTxs = flattenMempoolContent(content);
    
    // Update local cache
    for (const tx of allTxs) {
      this.transactions.set(tx.hash, tx);
    }
    
    console.log(`Synced: ${this.transactions.size} transactions in mempool`);
  }
  
  async getTransaction(hash) {
    const response = await fetch(this.rpcUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jsonrpc: '2.0',
        method: 'eth_getTransactionByHash',
        params: [hash],
        id: 1
      })
    });
    
    const data = await response.json();
    return data.result;
  }
  
  async getMempoolContent() {
    const response = await fetch(this.rpcUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jsonrpc: '2.0',
        method: 'txpool_content',
        params: [],
        id: 1
      })
    });
    
    const data = await response.json();
    return data.result;
  }
}

// Usage
const monitor = new MempoolMonitor(
  'http://localhost:8546',
  'ws://localhost:8547'
);
monitor.start();
```

### Example 3: Filter Transactions Theo Tiêu Chí

```javascript
async function filterMempoolTransactions(criteria) {
  const content = await getMempoolContent();
  const allTxs = flattenMempoolContent(content);
  
  return allTxs.filter(tx => {
    // Filter by value
    if (criteria.minValue) {
      const value = BigInt(tx.value);
      if (value < BigInt(criteria.minValue)) return false;
    }
    
    // Filter by gas price
    if (criteria.minGasPrice) {
      const gasPrice = BigInt(tx.gasPrice || tx.maxFeePerGas || '0');
      if (gasPrice < BigInt(criteria.minGasPrice)) return false;
    }
    
    // Filter by address
    if (criteria.from) {
      if (tx.from.toLowerCase() !== criteria.from.toLowerCase()) return false;
    }
    
    if (criteria.to) {
      if (!tx.to || tx.to.toLowerCase() !== criteria.to.toLowerCase()) return false;
    }
    
    // Filter by status
    if (criteria.status) {
      if (tx.status !== criteria.status) return false;
    }
    
    return true;
  });
}

// Usage
const highValueTxs = await filterMempoolTransactions({
  minValue: '1000000000000000000', // 1 ETH
  status: 'pending'
});

console.log(`Found ${highValueTxs.length} high-value transactions`);
```

---

## 📊 So Sánh Các Phương Pháp

| Method | Use Case | Latency | Data Size | Real-time |
|--------|----------|---------|-----------|-----------|
| `txpool_status` | Đếm số lượng | ~1ms | Nhỏ | ❌ |
| `txpool_content` | Lấy tất cả | ~5-10ms | Lớn | ❌ |
| `txpool_contentFrom` | Lấy theo address | ~2-5ms | Trung bình | ❌ |
| `txpool_inspect` | Xem tóm tắt | ~5-10ms | Trung bình | ❌ |
| `eth_pendingTransactions` | Local accounts | ~2-5ms | Trung bình | ❌ |
| `eth_subscribe` | Real-time monitor | ~1-5ms | Nhỏ | ✅ |

---

## 🎯 Best Practices

### 1. Sử Dụng WebSocket Cho Real-time Monitoring

```javascript
// ✅ Tốt: WebSocket subscription
const ws = new WebSocket('ws://localhost:8547');
ws.send(JSON.stringify({
  method: 'eth_subscribe',
  params: ['newPendingTransactions']
}));

// ❌ Không tốt: Polling
setInterval(async () => {
  const content = await getMempoolContent();
  // Process...
}, 100); // Polling mỗi 100ms
```

### 2. Cache và Sync Định Kỳ

```javascript
// Cache local và sync định kỳ
let mempoolCache = new Map();

// WebSocket cho real-time updates
ws.on('message', (data) => {
  // Update cache khi có transaction mới
});

// Sync định kỳ để đảm bảo không miss
setInterval(async () => {
  const content = await getMempoolContent();
  // Update cache
}, 5000); // Sync mỗi 5 giây
```

### 3. Batch Processing

```javascript
// Xử lý theo batch để tránh overload
async function processMempoolBatch(batchSize = 100) {
  const content = await getMempoolContent();
  const allTxs = flattenMempoolContent(content);
  
  for (let i = 0; i < allTxs.length; i += batchSize) {
    const batch = allTxs.slice(i, i + batchSize);
    await processBatch(batch);
    
    // Delay giữa các batch
    await sleep(100);
  }
}
```

### 4. Error Handling

```javascript
async function getMempoolContentSafe() {
  try {
    return await getMempoolContent();
  } catch (error) {
    console.error('Error getting mempool:', error);
    // Return empty structure
    return { pending: {}, queued: {} };
  }
}
```

---

## 🔍 Debugging Tips

### 1. Kiểm Tra Mempool Status

```bash
# Sử dụng curl
curl -X POST http://localhost:8546 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"txpool_status","params":[],"id":1}'
```

### 2. Xem Mempool Inspect

```bash
curl -X POST http://localhost:8546 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"txpool_inspect","params":[],"id":1}'
```

### 3. Test WebSocket

```javascript
// Test WebSocket connection
const ws = new WebSocket('ws://localhost:8547');
ws.on('open', () => console.log('Connected'));
ws.on('error', (err) => console.error('Error:', err));
ws.on('close', () => console.log('Closed'));
```

---

## 📝 Tóm Tắt

### Các RPC Methods:

1. **`txpool_status`** - Đếm số lượng (nhanh nhất)
2. **`txpool_content`** - Lấy tất cả transactions (đầy đủ nhất)
3. **`txpool_contentFrom`** - Lấy theo address (tiện lợi)
4. **`txpool_inspect`** - Xem tóm tắt (dễ đọc)
5. **`eth_pendingTransactions`** - Local accounts only

### WebSocket:

- **`eth_subscribe`** - Real-time monitoring (tốt nhất cho real-time)

### Khi Nào Dùng Gì:

- **Real-time monitoring**: WebSocket subscription
- **One-time query**: `txpool_content`
- **Count only**: `txpool_status`
- **Specific address**: `txpool_contentFrom`
- **Human-readable**: `txpool_inspect`

---

**Chúc bạn thành công với việc lấy và monitor mempool!** 🎉

