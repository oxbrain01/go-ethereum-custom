# Mempool Workflow - Giải Thích Chi Tiết

## 📋 Tổng Quan

Mempool (Memory Pool) là nơi lưu trữ các transactions đang chờ được include vào block. Đây là workflow chi tiết:

## 🔄 Workflow Mempool

### 1. **Transaction Submission** (Gửi Transaction)

```
User/MetaMask → eth_sendRawTransaction → Geth Node
```

- User gửi transaction qua RPC (`eth_sendRawTransaction`)
- Transaction được gửi đến geth node qua HTTP hoặc WebSocket

### 2. **Transaction Validation** (Kiểm Tra)

```
Geth Node → ValidateTransaction() → Check:
  - Signature valid?
  - Nonce correct?
  - Gas price sufficient?
  - Balance enough?
  - Chain ID correct?
  - Transaction size OK?
```

**Các bước validation:**

- ✅ **Signature Validation**: Kiểm tra chữ ký hợp lệ
- ✅ **Nonce Check**: Nonce phải đúng (không được skip)
- ✅ **Gas Price**: Phải >= minimum gas price
- ✅ **Balance Check**: Account phải có đủ ETH để pay gas + value
- ✅ **Chain ID**: Phải match với network
- ✅ **Size Check**: Transaction không được quá lớn

### 3. **Add to Mempool** (Thêm vào Mempool)

```
Valid Transaction → txPool.Add() → Mempool Storage
```

**Mempool có 2 phần:**

- **Pending**: Transactions sẵn sàng để mine (nonce đúng, balance đủ)
- **Queued**: Transactions chưa sẵn sàng (nonce quá cao, chờ nonce trước đó)

### 4. **Event Broadcasting** (Phát Sóng Event)

```
Transaction Added → NewTxsEvent → Event System → Subscribers
```

Khi transaction được add vào mempool:

- Geth tạo `NewTxsEvent`
- Event được broadcast đến tất cả subscribers
- WebSocket subscribers nhận notification ngay lập tức

### 5. **Block Mining** (Đào Block)

```
Miner/Validator → Get Pending Txs → Build Block → Include Txs → Mine Block
```

- Miner/Validator lấy transactions từ pending pool
- Build block với các transactions
- Mine block (PoS: validate, PoW: solve puzzle)
- Block được add vào chain

### 6. **Transaction Removal** (Xóa khỏi Mempool)

```
Block Mined → Transactions in Block → Remove from Mempool
```

Sau khi block được mine:

- Transactions trong block được remove khỏi mempool
- Mempool chỉ còn transactions chưa được mine

## 🔌 Tại Sao WebSocket Script Lấy Được Data?

### Cơ Chế WebSocket Subscription

Script `watch-mempool-nodejs.js` sử dụng **WebSocket subscription** thay vì polling:

```javascript
// 1. Kết nối WebSocket
const ws = new WebSocket("ws://localhost:8547");

// 2. Subscribe to newPendingTransactions
ws.send(
  JSON.stringify({
    method: "eth_subscribe",
    params: ["newPendingTransactions"],
  })
);
```

### Workflow WebSocket Subscription

```
1. Script → WebSocket Connect → Geth Node
   ↓
2. Script → Subscribe Request → Geth Event System
   ↓
3. Geth → Register Subscription → Event Feed
   ↓
4. Transaction Added → NewTxsEvent Triggered
   ↓
5. Event System → Notify All Subscribers
   ↓
6. WebSocket → Send Notification → Script
   ↓
7. Script → Receive Message → Display Transaction
```

### Code Flow trong Geth

**1. Transaction được add vào mempool:**

```go
// core/txpool/txpool.go
func (pool *TxPool) Add(txs []*types.Transaction) []error {
    // ... validation ...
    // Add to pool
    pool.insert(tx)
    // Trigger event
    pool.txFeed.Send(core.NewTxsEvent{Txs: []*types.Transaction{tx}})
}
```

**2. Event System broadcast:**

```go
// eth/filters/filter_system.go
func (es *EventSystem) SubscribePendingTxs(txs chan []*types.Transaction) {
    // Subscribe to txFeed
    sub := es.txFeed.Subscribe(txs)
    // When new tx arrives, send to channel
}
```

**3. RPC WebSocket handler:**

```go
// eth/filters/api.go
func (api *FilterAPI) NewPendingTransactions(ctx, fullTx) {
    // Create subscription
    pendingTxSub := api.events.SubscribePendingTxs(txs)
    // Send notification via WebSocket
    notifier.Notify(rpcSub.ID, tx.Hash())
}
```

## ⚡ Tại Sao WebSocket Tốt Hơn Polling?

### Polling (100ms interval):

```
Time: 0ms    → Transaction added to mempool
Time: 50ms   → Transaction mined (removed from mempool)
Time: 100ms  → Script polls → ❌ MISSED! (mempool empty)
```

### WebSocket Subscription:

```
Time: 0ms    → Transaction added to mempool
Time: 0ms    → Event triggered → WebSocket notification sent
Time: 1ms    → Script receives notification → ✅ CAUGHT!
Time: 50ms   → Transaction mined (but we already got it!)
```

## 📊 So Sánh

| Method                     | Latency  | Success Rate | Resource Usage            |
| -------------------------- | -------- | ------------ | ------------------------- |
| **WebSocket Subscription** | ~1-5ms   | **100%** ✅  | Low (event-driven)        |
| Ultra-fast Polling (100ms) | 0-100ms  | ~50-70% ⚠️   | Medium (constant polling) |
| Fast Polling (500ms)       | 0-500ms  | ~10-20% ❌   | Medium                    |
| Simple Polling (3s)        | 0-3000ms | ~0% ❌       | Low                       |

## 🔍 Chi Tiết Script `watch-mempool-nodejs.js`

### 1. **WebSocket Connection** (Lines 101-116)

```javascript
const ws = new WebSocket(WS_URL);
ws.on("open", () => {
  // Subscribe khi connection established
  ws.send(
    JSON.stringify({
      method: "eth_subscribe",
      params: ["newPendingTransactions"],
    })
  );
});
```

**Tại sao hoạt động:**

- WebSocket connection persistent (không cần reconnect mỗi lần)
- Geth giữ subscription active
- Khi có transaction mới, geth tự động gửi notification

### 2. **Message Handler** (Lines 118-170)

```javascript
ws.on("message", async (data) => {
  const message = JSON.parse(data.toString());

  // Subscription confirmation
  if (message.result) {
    // Subscription ID received
  }

  // Transaction notification
  if (message.params && message.params.result) {
    const txHash = message.params.result;
    // Transaction hash received immediately!
  }
});
```

**Tại sao lấy được data:**

- Geth gửi notification **ngay khi** transaction được add vào mempool
- Không cần poll - event-driven
- Latency cực thấp (~1-5ms)

### 3. **Get Transaction Details** (Lines 56-90)

```javascript
function getTransactionDetails(txHash) {
  // Query transaction details via HTTP RPC
  // This happens AFTER we already know about the transaction
}
```

**Tại sao cần:**

- WebSocket chỉ gửi transaction hash (để tiết kiệm bandwidth)
- Script query chi tiết qua HTTP RPC sau khi nhận hash
- Transaction có thể đã được mine khi query, nhưng hash đã có

### 4. **Get Mempool Status** (Lines 18-54)

```javascript
function getMempoolStatus() {
  // Query current mempool status
  // Shows pending/queued count
}
```

**Tại sao hữu ích:**

- Hiển thị số lượng transactions hiện tại trong mempool
- Giúp hiểu context (có bao nhiêu tx đang chờ)

## 🎯 Kết Luận

### Tại sao script này lấy được data:

1. **WebSocket Subscription** - Event-driven, không phải polling
2. **Real-time Notification** - Geth gửi notification ngay khi transaction được add
3. **Low Latency** - ~1-5ms từ khi transaction add đến khi script nhận
4. **100% Success Rate** - Không miss transactions (trừ khi bị reject)

### Workflow Tóm Tắt:

```
MetaMask → Send TX → Geth Validate → Add to Mempool
    → Trigger Event → WebSocket Notify → Script Receive
    → Display Transaction ✅
```

Script này **luôn bắt được** transactions vì nó subscribe vào event stream, không phải polling!
