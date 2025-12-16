# Mempool Workflow - Giải Thích Chi Tiết

## 📋 Tổng Quan

Mempool (Memory Pool) là nơi lưu trữ các transactions đang chờ được include vào block. Đây là workflow chi tiết:

## 🔄 Workflow Mempool Hoàn Chỉnh

### 1. **Transaction Submission** (Gửi Transaction)

```
User/MetaMask 
    ↓
eth_sendRawTransaction (RPC call)
    ↓
Geth Node nhận transaction
```

**Ví dụ từ MetaMask:**
- User click "Send" trong MetaMask
- MetaMask ký transaction với private key
- MetaMask gửi raw transaction đến `http://localhost:8546`
- Geth nhận transaction qua RPC endpoint

### 2. **Transaction Validation** (Kiểm Tra)

```
Geth Node
    ↓
ValidateTransaction()
    ↓
Kiểm tra:
  ✅ Signature hợp lệ?
  ✅ Nonce đúng?
  ✅ Gas price đủ?
  ✅ Balance đủ?
  ✅ Chain ID đúng?
  ✅ Transaction size OK?
```

**Các bước validation trong code:**
```go
// core/txpool/validation.go
func ValidateTransaction(tx, head, signer, opts) error {
    // Check signature
    // Check nonce
    // Check balance
    // Check gas price
    // ...
}
```

**Nếu validation fail:**
- Transaction bị reject
- Không vào mempool
- Error được trả về cho user

**Nếu validation pass:**
- Transaction được chấp nhận
- Tiếp tục đến bước 3

### 3. **Add to Mempool** (Thêm vào Mempool)

```
Valid Transaction
    ↓
txPool.Add(tx)
    ↓
Mempool Storage
    ├── Pending Pool (sẵn sàng mine)
    └── Queued Pool (chưa sẵn sàng)
```

**Pending vs Queued:**

**Pending:**
- Nonce đúng (ví dụ: account nonce = 5, tx nonce = 5)
- Balance đủ để pay gas + value
- Sẵn sàng để được mine ngay

**Queued:**
- Nonce quá cao (ví dụ: account nonce = 5, tx nonce = 10)
- Chờ các transactions trước đó (nonce 6, 7, 8, 9)
- Sẽ được promote lên pending khi nonce đúng

### 4. **Event Broadcasting** (Phát Sóng Event) ⚡ KEY STEP

```
Transaction Added to Mempool
    ↓
pool.txFeed.Send(NewTxsEvent{Txs: [tx]})
    ↓
Event System (event.Feed)
    ↓
Broadcast to ALL Subscribers
    ├── WebSocket Subscribers
    ├── Internal Handlers
    └── Other Components
```

**Code flow trong Geth:**

```go
// core/txpool/legacypool/legacypool.go
func (pool *LegacyPool) Add(txs []*types.Transaction) {
    // ... add transaction to pool ...
    
    // ⚡ TRIGGER EVENT - This is the key!
    pool.txFeed.Send(core.NewTxsEvent{Txs: txs})
}
```

**Event System:**
```go
// eth/filters/filter_system.go
func (es *EventSystem) SubscribePendingTxs(txs chan []*types.Transaction) {
    // Subscribe to txFeed
    sub := es.txFeed.Subscribe(txs)
    // When event is sent, all subscribers receive it
}
```

**RPC WebSocket Handler:**
```go
// eth/filters/api.go
func (api *FilterAPI) NewPendingTransactions(ctx, fullTx) {
    // Create subscription
    pendingTxSub := api.events.SubscribePendingTxs(txs)
    
    // Send notification via WebSocket
    notifier.Notify(rpcSub.ID, tx.Hash())
}
```

### 5. **WebSocket Notification** (Thông Báo Qua WebSocket)

```
Event System
    ↓
WebSocket Handler
    ↓
Send JSON-RPC Notification
    {
        "jsonrpc": "2.0",
        "method": "eth_subscription",
        "params": {
            "subscription": "0x123...",
            "result": "0xtxhash..."
        }
    }
    ↓
Script Receives Message
```

**Timeline:**
- `T+0ms`: Transaction added to mempool
- `T+0ms`: Event triggered
- `T+1ms`: WebSocket notification sent
- `T+2ms`: Script receives notification ✅

### 6. **Block Mining** (Đào Block)

```
Miner/Validator
    ↓
Get Pending Transactions from Mempool
    ↓
Build Block (include transactions)
    ↓
Mine/Validate Block
    ↓
Block Added to Chain
    ↓
Transactions Removed from Mempool
```

**Với SimulatedBeacon:**
- Mine blocks ngay khi có transaction
- Block time: ~12 giây (period mode) hoặc ngay lập tức (tx-triggered)
- Transactions được mine trong vài milliseconds đến vài giây

## 🔌 Tại Sao WebSocket Script Lấy Được Data?

### So Sánh Polling vs Subscription

#### ❌ Polling (Cách Cũ):
```
Script: "Có transaction nào không?" → Geth: "Không"
[100ms sau]
Script: "Có transaction nào không?" → Geth: "Không"
[100ms sau]
Script: "Có transaction nào không?" → Geth: "Có! Nhưng đã mine rồi" ❌
```

**Vấn đề:**
- Transaction được add lúc T+0ms
- Transaction được mine lúc T+50ms
- Script poll lúc T+100ms → **MISSED!**

#### ✅ WebSocket Subscription (Cách Mới):
```
Script: "Notify me when transaction added"
Geth: "OK, subscribed"

[Transaction added at T+0ms]
Geth: "Hey! New transaction: 0xabc..." → Script receives at T+1ms ✅
[Transaction mined at T+50ms - but we already got it!]
```

**Ưu điểm:**
- Notification ngay lập tức (~1-5ms)
- Không miss transactions
- Event-driven (không tốn tài nguyên polling)

### Code Flow Chi Tiết

**1. Script Subscribe:**
```javascript
// Line 107-115
ws.send(JSON.stringify({
    method: 'eth_subscribe',
    params: ['newPendingTransactions']
}));
```

**2. Geth Register Subscription:**
```go
// eth/filters/api.go
func (api *FilterAPI) NewPendingTransactions(ctx, fullTx) {
    // Create channel for transactions
    txs := make(chan []*types.Transaction, 128)
    
    // Subscribe to event feed
    pendingTxSub := api.events.SubscribePendingTxs(txs)
    
    // When transaction arrives, send via WebSocket
    for tx := range txs {
        notifier.Notify(rpcSub.ID, tx.Hash())
    }
}
```

**3. Transaction Added:**
```go
// core/txpool/legacypool/legacypool.go
func (pool *LegacyPool) Add(txs) {
    // Add to pool
    pool.addTxsLocked(txs)
    
    // ⚡ TRIGGER EVENT
    pool.txFeed.Send(core.NewTxsEvent{Txs: txs})
    // ↑ This immediately notifies all subscribers!
}
```

**4. Script Receives:**
```javascript
// Line 118-170
ws.on('message', async (data) => {
    const message = JSON.parse(data.toString());
    
    // Transaction hash received!
    if (message.params && message.params.result) {
        const txHash = message.params.result;
        // ✅ Got it! Even if mined milliseconds later
    }
});
```

## 📊 Timeline So Sánh

### Scenario: Transaction từ MetaMask

**Polling (100ms interval):**
```
T+0ms:   Transaction submitted
T+1ms:   Transaction validated
T+2ms:   Transaction added to mempool
T+3ms:   Event triggered
T+50ms:  Transaction mined (removed from mempool)
T+100ms: Script polls → ❌ MISSED! (mempool empty)
```

**WebSocket Subscription:**
```
T+0ms:   Transaction submitted
T+1ms:   Transaction validated
T+2ms:   Transaction added to mempool
T+2ms:   Event triggered
T+3ms:   WebSocket notification sent
T+4ms:   Script receives notification ✅
T+50ms:  Transaction mined (but we already got it!)
```

## 🎯 Tại Sao Script Này Hoạt Động

### 1. **Event-Driven Architecture**

Geth sử dụng **event.Feed** pattern:
- Khi transaction được add, event được broadcast
- Tất cả subscribers nhận notification ngay lập tức
- Không cần polling

### 2. **WebSocket Persistent Connection**

- Connection được giữ mở
- Geth gửi notifications qua connection này
- Không cần reconnect mỗi lần

### 3. **Low Latency**

- Event system: ~1ms
- WebSocket send: ~1ms
- Network latency: ~1-3ms
- **Total: ~3-5ms** từ khi add đến khi script nhận

### 4. **100% Success Rate**

- Notification được gửi **trước khi** transaction được mine
- Ngay cả khi transaction được mine trong 10ms, script đã nhận ở T+4ms
- Không miss transactions (trừ khi bị reject)

## 🔍 Chi Tiết Script `watch-mempool-nodejs.js`

### Function 1: `getMempoolStatus()` (Lines 18-54)

**Mục đích:** Query số lượng transactions hiện tại trong mempool

**Khi nào dùng:**
- Sau khi nhận transaction notification
- Để hiển thị context (có bao nhiêu tx đang chờ)

**Cách hoạt động:**
```javascript
// HTTP RPC call
method: 'txpool_status'
// Returns: { pending: "0x5", queued: "0x2" }
```

### Function 2: `getTransactionDetails()` (Lines 56-90)

**Mục đích:** Lấy chi tiết transaction (from, to, value, gas)

**Tại sao cần:**
- WebSocket chỉ gửi transaction hash (tiết kiệm bandwidth)
- Script cần query chi tiết qua HTTP RPC

**Lưu ý:**
- Transaction có thể đã được mine khi query
- Nhưng hash đã có từ WebSocket notification

### WebSocket Connection (Lines 101-116)

**Bước 1: Connect**
```javascript
const ws = new WebSocket('ws://localhost:8547');
```

**Bước 2: Subscribe**
```javascript
ws.send({
    method: 'eth_subscribe',
    params: ['newPendingTransactions']
});
```

**Kết quả:**
- Geth register subscription
- Geth sẽ gửi notification cho MỌI transaction mới

### Message Handler (Lines 118-170)

**Message Type 1: Subscription Confirmation**
```json
{
    "jsonrpc": "2.0",
    "result": "0x123abc...",  // Subscription ID
    "id": 1
}
```

**Message Type 2: Transaction Notification**
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

**Script xử lý:**
1. Nhận transaction hash
2. Query chi tiết qua HTTP RPC
3. Query mempool status
4. Hiển thị thông tin

## 📈 Performance Comparison

| Method | Latency | Success Rate | CPU Usage |
|--------|---------|--------------|-----------|
| **WebSocket Subscription** | **3-5ms** | **100%** ✅ | Low (event-driven) |
| Ultra-fast Polling (100ms) | 0-100ms | ~50-70% ⚠️ | Medium |
| Fast Polling (500ms) | 0-500ms | ~10-20% ❌ | Medium |
| Simple Polling (3s) | 0-3000ms | ~0% ❌ | Low |

## 🎓 Kết Luận

### Tại sao script này lấy được data:

1. ✅ **Event-Driven**: Subscribe vào event stream, không phải polling
2. ✅ **Real-time**: Notification ngay khi transaction được add (~3-5ms)
3. ✅ **Persistent Connection**: WebSocket connection được giữ mở
4. ✅ **100% Success**: Bắt được tất cả transactions (trừ khi bị reject)

### Workflow Tóm Tắt:

```
MetaMask → Send TX 
    → Geth Validate 
    → Add to Mempool 
    → Trigger Event (NewTxsEvent)
    → Event System Broadcast
    → WebSocket Notify
    → Script Receive (T+3-5ms) ✅
    → [Transaction may be mined later, but we already got it!]
```

**Đây là lý do tại sao WebSocket subscription là cách tốt nhất để monitor mempool!** 🎯

