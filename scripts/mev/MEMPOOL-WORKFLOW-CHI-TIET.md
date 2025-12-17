# Mempool Workflow - Hướng Dẫn Chi Tiết Từ Source Code

## 📋 Mục Lục

1. [Tổng Quan Kiến Trúc](#tổng-quan-kiến-trúc)
2. [Workflow Hoàn Chỉnh](#workflow-hoàn-chỉnh)
3. [Chi Tiết Từng Bước Với Code](#chi-tiết-từng-bước-với-code)
4. [Event System & WebSocket](#event-system--websocket)
5. [Mining & Transaction Selection](#mining--transaction-selection)
6. [Các Thành Phần Chính](#các-thành-phần-chính)

---

## 🏗️ Tổng Quan Kiến Trúc

### Cấu Trúc Mempool trong Geth

```
┌─────────────────────────────────────────────────────────┐
│                    TxPool (Main)                        │
│  core/txpool/txpool.go                                  │
│  - Quản lý nhiều subpools                                │
│  - Điều phối transactions                                │
│  - SubscribeTransactions() → Event Feed                  │
└─────────────────────────────────────────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        │               │               │
┌───────▼──────┐ ┌───────▼──────┐ ┌─────▼──────┐
│ LegacyPool  │ │  BlobPool    │ │ Other Pools│
│ (EVM txs)   │ │ (Blob txs)   │ │            │
└─────────────┘ └──────────────┘ └────────────┘
        │               │
        │               │
┌───────▼───────────────▼───────────────┐
│         Pending Pool                  │
│  - Nonce đúng                         │
│  - Balance đủ                          │
│  - Sẵn sàng để mine                   │
└───────────────────────────────────────┘
        │
┌───────▼───────────────┐
│      Queued Pool      │
│  - Nonce quá cao       │
│  - Chờ nonce trước    │
└───────────────────────┘
```

### Luồng Dữ Liệu Tổng Quan

```
User/App
    │
    ├─► RPC: eth_sendRawTransaction
    │       │
    │       ▼
    │   internal/ethapi/api.go:SendRawTransaction()
    │       │
    │       ▼
    │   eth/api_backend.go:SendTx()
    │       │
    │       ▼
    │   core/txpool/txpool.go:Add()
    │       │
    │       ├─► core/txpool/legacypool:Add()
    │       │       │
    │       │       ├─► Validation
    │       │       ├─► Add to Pending/Queued
    │       │       └─► Trigger Event ⚡
    │       │
    │       └─► Event Feed
    │               │
    │               ▼
    │           eth/filters/filter_system.go
    │               │
    │               ▼
    │           eth/filters/api.go:NewPendingTransactions()
    │               │
    │               ▼
    │           WebSocket Notification
    │               │
    │               ▼
    │           Script/Client nhận notification
    │
    └─► Miner
            │
            ▼
        miner/worker.go
            │
            ▼
        Lấy transactions từ Pending Pool
            │
            ▼
        Build Block
            │
            ▼
        Mine Block
            │
            ▼
        Remove transactions khỏi mempool
```

---

## 🔄 Workflow Hoàn Chỉnh

### Timeline Chi Tiết

```
T+0ms:   User gửi transaction (MetaMask/App)
T+1ms:   RPC nhận: eth_sendRawTransaction
T+2ms:   Validation bắt đầu
T+5ms:   Validation pass → Add vào mempool
T+5ms:   Event triggered (NewTxsEvent)
T+6ms:   WebSocket notification gửi
T+7ms:   Script nhận notification ✅
T+50ms:  Miner lấy transaction
T+100ms: Block được mine
T+101ms: Transaction removed khỏi mempool
```

---

## 📝 Chi Tiết Từng Bước Với Code

### Bước 1: Transaction Submission (Gửi Transaction)

**Entry Point:** `internal/ethapi/api.go`

```go
// Line 1648-1669
func (api *TransactionAPI) SendRawTransaction(ctx context.Context, input hexutil.Bytes) (common.Hash, error) {
    // 1. Parse transaction từ raw bytes
    tx := new(types.Transaction)
    if err := tx.UnmarshalBinary(input); err != nil {
        return common.Hash{}, err
    }
    
    // 2. Convert blob transaction nếu cần
    if sc := tx.BlobTxSidecar(); sc != nil {
        // ... conversion logic ...
    }
    
    // 3. Submit transaction
    return SubmitTransaction(ctx, api.b, tx)
}
```

**SubmitTransaction:** `internal/ethapi/api.go:1551`

```go
func SubmitTransaction(ctx context.Context, b Backend, tx *types.Transaction) (common.Hash, error) {
    // 1. Kiểm tra fee cap
    if err := checkTxFee(tx.GasPrice(), tx.Gas(), b.RPCTxFeeCap()); err != nil {
        return common.Hash{}, err
    }
    
    // 2. Kiểm tra EIP-155 protection
    if !b.UnprotectedAllowed() && !tx.Protected() {
        return common.Hash{}, errors.New("only replay-protected transactions allowed")
    }
    
    // 3. Gửi đến transaction pool
    if err := b.SendTx(ctx, tx); err != nil {
        return common.Hash{}, err
    }
    
    // 4. Log transaction
    log.Info("Submitted transaction", "hash", tx.Hash().Hex(), ...)
    
    return tx.Hash(), nil
}
```

**Backend SendTx:** `eth/api_backend.go:322`

```go
func (b *EthAPIBackend) SendTx(ctx context.Context, signedTx *types.Transaction) error {
    // ⚡ KEY STEP: Add transaction vào pool
    err := b.eth.txPool.Add([]*types.Transaction{signedTx}, false)[0]
    
    // Handle local transaction tracking nếu có
    if b.eth.localTxTracker != nil {
        // Track transaction để retry nếu cần
        b.eth.localTxTracker.Track(signedTx)
    }
    
    return err
}
```

---

### Bước 2: Transaction Validation (Kiểm Tra)

**Main Pool Add:** `core/txpool/txpool.go:314`

```go
func (p *TxPool) Add(txs []*types.Transaction, sync bool) []error {
    // 1. Phân loại transactions vào các subpools
    txsets := make([][]*types.Transaction, len(p.subpools))
    splits := make([]int, len(txs))
    
    for i, tx := range txs {
        splits[i] = -1
        // Tìm subpool phù hợp (LegacyPool, BlobPool, ...)
        for j, subpool := range p.subpools {
            if subpool.Filter(tx) {
                txsets[j] = append(txsets[j], tx)
                splits[i] = j
                break
            }
        }
    }
    
    // 2. Add transactions vào từng subpool
    errsets := make([][]error, len(p.subpools))
    for i := 0; i < len(p.subpools); i++ {
        errsets[i] = p.subpools[i].Add(txsets[i], sync)
    }
    
    // 3. Merge errors và return
    // ...
    return errs
}
```

**LegacyPool Add:** `core/txpool/legacypool/legacypool.go:904`

```go
func (pool *LegacyPool) Add(txs []*types.Transaction, sync bool) []error {
    var (
        errs = make([]error, len(txs))
        news = make([]*types.Transaction, 0, len(txs))
    )
    
    // 1. Filter known transactions (đã có trong pool)
    for i, tx := range txs {
        if pool.all.Get(tx.Hash()) != nil {
            errs[i] = txpool.ErrAlreadyKnown
            continue
        }
        
        // 2. Validate basics (signature, intrinsic gas, ...)
        if err := pool.ValidateTxBasics(tx); err != nil {
            errs[i] = err
            invalidTxMeter.Mark(1)
            continue
        }
        
        news = append(news, tx)
    }
    
    if len(news) == 0 {
        return errs
    }
    
    // 3. Add transactions với lock
    pool.mu.Lock()
    newErrs, dirtyAddrs := pool.addTxsLocked(news)
    pool.mu.Unlock()
    
    // 4. Promote executables (queued → pending)
    done := pool.requestPromoteExecutables(dirtyAddrs)
    if sync {
        <-done
    }
    
    return errs
}
```

**Validation:** `core/txpool/validation.go:61`

```go
func ValidateTransaction(tx *types.Transaction, head *types.Header, signer types.Signer, opts *ValidationOptions) error {
    // 1. Kiểm tra transaction type được support
    if opts.Accept&(1<<tx.Type()) == 0 {
        return fmt.Errorf("tx type %v not supported", tx.Type())
    }
    
    // 2. Kiểm tra size
    if tx.Size() > opts.MaxSize {
        return fmt.Errorf("transaction size %v, limit %v", tx.Size(), opts.MaxSize)
    }
    
    // 3. Kiểm tra fork rules (Berlin, London, Cancun, ...)
    rules := opts.Config.Rules(head.Number, head.Difficulty.Sign() == 0, head.Time)
    if !rules.IsBerlin && tx.Type() != types.LegacyTxType {
        return fmt.Errorf("pool not yet in Berlin")
    }
    // ... more fork checks ...
    
    // 4. Kiểm tra value không âm
    if tx.Value().Sign() < 0 {
        return ErrNegativeValue
    }
    
    // 5. Kiểm tra gas limit
    if head.GasLimit < tx.Gas() {
        return ErrGasLimit
    }
    
    // 6. Kiểm tra fee cap và tip cap
    if tx.GasFeeCapIntCmp(tx.GasTipCap()) < 0 {
        return core.ErrTipAboveFeeCap
    }
    
    // 7. Kiểm tra signature
    if _, err := types.Sender(signer, tx); err != nil {
        return fmt.Errorf("%w: %v", ErrInvalidSender, err)
    }
    
    // 8. Kiểm tra intrinsic gas
    intrGas, err := core.IntrinsicGas(tx.Data(), tx.AccessList(), ...)
    if tx.Gas() < intrGas {
        return fmt.Errorf("gas %v, minimum needed %v", tx.Gas(), intrGas)
    }
    
    // 9. Kiểm tra gas tip đủ cao
    if tx.GasTipCapIntCmp(opts.MinTip) < 0 {
        return fmt.Errorf("gas tip cap %v, minimum needed %v", tx.GasTipCap(), opts.MinTip)
    }
    
    return nil
}
```

**State Validation:** `core/txpool/validation.go:239`

```go
func ValidateTransactionWithState(tx *types.Transaction, signer types.Signer, opts *ValidationOptionsWithState) error {
    from, err := types.Sender(signer, tx)
    if err != nil {
        return err
    }
    
    // 1. Kiểm tra nonce
    next := opts.State.GetNonce(from)
    if next > tx.Nonce() {
        return fmt.Errorf("next nonce %v, tx nonce %v", next, tx.Nonce())
    }
    
    // 2. Kiểm tra nonce gap
    if opts.FirstNonceGap != nil {
        if gap := opts.FirstNonceGap(from); gap < tx.Nonce() {
            return fmt.Errorf("tx nonce %v, gapped nonce %v", tx.Nonce(), gap)
        }
    }
    
    // 3. Kiểm tra balance đủ
    balance := opts.State.GetBalance(from).ToBig()
    cost := tx.Cost()
    if balance.Cmp(cost) < 0 {
        return fmt.Errorf("balance %v, tx cost %v", balance, cost)
    }
    
    // 4. Kiểm tra balance đủ cho replacement
    spent := opts.ExistingExpenditure(from)
    if prev := opts.ExistingCost(from, tx.Nonce()); prev != nil {
        bump := new(big.Int).Sub(cost, prev)
        need := new(big.Int).Add(spent, bump)
        if balance.Cmp(need) < 0 {
            return fmt.Errorf("insufficient funds for replacement")
        }
    }
    
    return nil
}
```

---

### Bước 3: Add to Mempool (Thêm vào Mempool)

**addTxsLocked:** `core/txpool/legacypool/legacypool.go:957`

```go
func (pool *LegacyPool) addTxsLocked(txs []*types.Transaction) ([]error, *accountSet) {
    var (
        dirty = newAccountSet(pool.signer)
        errs  = make([]error, len(txs))
        valid int64
    )
    
    for i, tx := range txs {
        // Add transaction vào pool
        replaced, err := pool.add(tx)
        errs[i] = err
        if err == nil {
            if !replaced {
                dirty.addTx(tx) // Đánh dấu account cần promote
            }
            valid++
        }
    }
    
    validTxMeter.Mark(valid)
    return errs, dirty
}
```

**add (internal):** `core/txpool/legacypool/legacypool.go` (simplified)

```go
func (pool *LegacyPool) add(tx *types.Transaction) (bool, error) {
    // 1. Validate transaction
    if err := pool.validateTx(tx); err != nil {
        return false, err
    }
    
    from, _ := types.Sender(pool.signer, tx)
    
    // 2. Kiểm tra xem có thể add vào pending không
    if pool.pending[from] != nil {
        // Có pending transactions, thử add vào list
        inserted, old := pool.pending[from].Add(tx, pool.config.PriceBump)
        if !inserted {
            return false, nil // Transaction cũ tốt hơn
        }
        // Replace transaction cũ nếu có
        if old != nil {
            pool.all.Remove(old.Hash())
            pool.priced.Removed(1)
        }
        return true, nil
    }
    
    // 3. Không có pending, thêm vào queue
    if pool.queue[from] == nil {
        pool.queue[from] = newTxList(true)
    }
    inserted, old := pool.queue[from].Add(tx, pool.config.PriceBump)
    if !inserted {
        return false, nil
    }
    
    // 4. Add vào all transactions map
    pool.all.Add(tx)
    pool.priced.Put(tx)
    
    return true, nil
}
```

**Pending vs Queued:**

- **Pending:** Transaction có nonce đúng, balance đủ, sẵn sàng để mine
- **Queued:** Transaction có nonce quá cao, chờ các transactions trước đó

---

### Bước 4: Event Broadcasting (Phát Sóng Event) ⚡ KEY STEP

**requestPromoteExecutables:** `core/txpool/legacypool/legacypool.go:1270`

```go
func (pool *LegacyPool) requestPromoteExecutables(accounts *accountSet) chan struct{} {
    // ... promotion logic ...
    
    // ⚡ TRIGGER EVENT - Đây là bước quan trọng!
    pool.mu.Unlock()
    
    // Notify subsystems for newly added transactions
    for _, tx := range promoted {
        addr, _ := types.Sender(pool.signer, tx)
        if _, ok := events[addr]; !ok {
            events[addr] = NewSortedMap()
        }
        events[addr].Put(tx)
    }
    
    if len(events) > 0 {
        var txs []*types.Transaction
        for _, set := range events {
            txs = append(txs, set.Flatten()...)
        }
        // ⚡ GỬI EVENT - Tất cả subscribers sẽ nhận ngay lập tức!
        pool.txFeed.Send(core.NewTxsEvent{Txs: txs})
    }
    
    return done
}
```

**Event Feed:** `core/txpool/txpool.go:374`

```go
func (p *TxPool) SubscribeTransactions(ch chan<- core.NewTxsEvent, reorgs bool) event.Subscription {
    subs := make([]event.Subscription, len(p.subpools))
    for i, subpool := range p.subpools {
        // Subscribe vào event feed của từng subpool
        subs[i] = subpool.SubscribeTransactions(ch, reorgs)
    }
    // Join tất cả subscriptions lại
    return p.subs.Track(event.JoinSubscriptions(subs...))
}
```

---

### Bước 5: WebSocket Notification (Thông Báo Qua WebSocket)

**Filter API:** `eth/filters/api.go:182`

```go
func (api *FilterAPI) NewPendingTransactions(ctx context.Context, fullTx *bool) (*rpc.Subscription, error) {
    // 1. Kiểm tra WebSocket support
    notifier, supported := rpc.NotifierFromContext(ctx)
    if !supported {
        return &rpc.Subscription{}, rpc.ErrNotificationsUnsupported
    }
    
    // 2. Tạo subscription
    rpcSub := notifier.CreateSubscription()
    
    // 3. Goroutine để handle events
    go func() {
        // Tạo channel để nhận transactions
        txs := make(chan []*types.Transaction, 128)
        
        // ⚡ Subscribe vào event system
        pendingTxSub := api.events.SubscribePendingTxs(txs)
        defer pendingTxSub.Unsubscribe()
        
        chainConfig := api.sys.backend.ChainConfig()
        
        for {
            select {
            case txs := <-txs:
                // ⚡ Nhận transactions từ event feed
                latest := api.sys.backend.CurrentHeader()
                for _, tx := range txs {
                    if fullTx != nil && *fullTx {
                        // Gửi full transaction object
                        rpcTx := ethapi.NewRPCPendingTransaction(tx, latest, chainConfig)
                        notifier.Notify(rpcSub.ID, rpcTx)
                    } else {
                        // ⚡ Gửi transaction hash (tiết kiệm bandwidth)
                        notifier.Notify(rpcSub.ID, tx.Hash())
                    }
                }
            case <-rpcSub.Err():
                return
            }
        }
    }()
    
    return rpcSub, nil
}
```

**Event System:** `eth/filters/filter_system.go:387`

```go
func (es *EventSystem) SubscribePendingTxs(txs chan []*types.Transaction) *Subscription {
    sub := &subscription{
        id:        rpc.NewID(),
        typ:       PendingTransactionsSubscription,
        created:   time.Now(),
        txs:       txs, // Channel để nhận transactions
        // ...
    }
    return es.subscribe(sub)
}
```

**Backend Connection:** `eth/api_backend.go:402`

```go
func (b *EthAPIBackend) SubscribeNewTxsEvent(ch chan<- core.NewTxsEvent) event.Subscription {
    // Subscribe vào transaction pool event feed
    return b.eth.txPool.SubscribeTransactions(ch, true)
}
```

**Flow Hoàn Chỉnh:**

```
Transaction Added
    │
    ▼
pool.txFeed.Send(NewTxsEvent{Txs: txs})
    │
    ▼
Event Feed Broadcast
    │
    ├─► EventSystem.SubscribePendingTxs()
    │       │
    │       ▼
    │   Channel: txs <- []*types.Transaction
    │       │
    │       ▼
    │   FilterAPI.NewPendingTransactions()
    │       │
    │       ▼
    │   notifier.Notify(rpcSub.ID, tx.Hash())
    │       │
    │       ▼
    │   WebSocket Send
    │       │
    │       ▼
    │   Script nhận notification ✅
```

---

### Bước 6: Block Mining (Đào Block)

**Miner Worker:** `miner/worker.go` (simplified)

```go
func (w *worker) commitNewWork() {
    // 1. Lấy pending transactions từ pool
    pending := w.eth.TxPool().Pending(txpool.PendingFilter{})
    
    // 2. Sắp xếp transactions theo price và nonce
    txs := newTransactionsByPriceAndNonce(w.current.signer, pending, w.current.header.BaseFee)
    
    // 3. Build block với transactions
    block, err := w.engine.FinalizeAndAssemble(w.chain, w.current.header, w.current.state, txs, ...)
    
    // 4. Mine block
    w.engine.Seal(w.chain, block, ...)
}
```

**Transaction Ordering:** `miner/ordering.go`

```go
// transactionsByPriceAndNonce sắp xếp transactions:
// 1. Theo gas price (cao nhất trước)
// 2. Theo nonce (trong cùng account)
// 3. Theo thời gian nhận (nếu price bằng nhau)

type transactionsByPriceAndNonce struct {
    txs     map[common.Address][]*txpool.LazyTransaction
    heads   txByPriceAndTime  // Heap theo price
    signer  types.Signer
    baseFee *uint256.Int
}
```

**Sau Khi Block Được Mine:**

```go
// core/txpool/legacypool/legacypool.go:reset()
func (pool *LegacyPool) reset(oldHead, newHead *types.Header) {
    // 1. Remove transactions đã được include trong block
    // 2. Promote queued transactions nếu nonce đã đúng
    // 3. Evict transactions quá cũ
}
```

---

## 🔌 Event System & WebSocket

### Event Feed Pattern

Geth sử dụng **event.Feed** pattern từ package `github.com/ethereum/go-ethereum/event`:

```go
type Feed struct {
    once      sync.Once
    sendLock  chan struct{}
    removeSub chan interface{}
    sendCases []reflect.SelectCase
    mu        sync.RWMutex
    inbox     []interface{}
    sendSub   subscriptionSet
}

func (f *Feed) Send(value interface{}) (nsent int) {
    // Broadcast value đến tất cả subscribers
    // Non-blocking, thread-safe
}
```

**Ưu điểm:**
- ✅ Non-blocking: Không block khi gửi event
- ✅ Thread-safe: An toàn với concurrent access
- ✅ Low latency: Event được gửi ngay lập tức
- ✅ Type-safe: Compile-time type checking

### WebSocket Subscription Flow

```
1. Client Connect
   ws://localhost:8547
        │
        ▼
2. Client Subscribe
   {"method": "eth_subscribe", "params": ["newPendingTransactions"]}
        │
        ▼
3. Geth Register
   FilterAPI.NewPendingTransactions()
   → EventSystem.SubscribePendingTxs()
   → Backend.SubscribeNewTxsEvent()
   → TxPool.SubscribeTransactions()
        │
        ▼
4. Event Triggered
   Transaction added → txFeed.Send()
        │
        ▼
5. Event Broadcast
   All subscribers receive event
        │
        ▼
6. WebSocket Notify
   notifier.Notify(subscriptionID, txHash)
        │
        ▼
7. Client Receive
   {"method": "eth_subscription", "params": {...}}
```

---

## ⛏️ Mining & Transaction Selection

### Transaction Selection Logic

**Ordering:** `miner/ordering.go`

```go
// Sắp xếp transactions theo:
// 1. Gas Price (effective miner tip) - CAO NHẤT TRƯỚC
// 2. Nonce order (trong cùng account)
// 3. Time received (nếu price bằng nhau)

func (s txByPriceAndTime) Less(i, j int) bool {
    // So sánh price
    cmp := s[i].fees.Cmp(s[j].fees)
    if cmp == 0 {
        // Nếu price bằng nhau, dùng thời gian
        return s[i].tx.Time.Before(s[j].tx.Time)
    }
    return cmp > 0 // Price cao hơn → ưu tiên hơn
}
```

**Effective Miner Fee:**

```go
// miner/ordering.go:39
func newTxWithMinerFee(tx *txpool.LazyTransaction, from common.Address, baseFee *uint256.Int) (*txWithMinerFee, error) {
    tip := new(uint256.Int).Set(tx.GasTipCap)
    if baseFee != nil {
        // Effective tip = min(gasTipCap, gasFeeCap - baseFee)
        if tx.GasFeeCap.Cmp(baseFee) < 0 {
            return nil, types.ErrGasFeeCapTooLow
        }
        tip = new(uint256.Int).Sub(tx.GasFeeCap, baseFee)
        if tip.Gt(tx.GasTipCap) {
            tip = tx.GasTipCap
        }
    }
    return &txWithMinerFee{tx: tx, from: from, fees: tip}, nil
}
```

---

## 🧩 Các Thành Phần Chính

### 1. TxPool (`core/txpool/txpool.go`)

**Chức năng:**
- Quản lý nhiều subpools (LegacyPool, BlobPool, ...)
- Điều phối transactions
- Cung cấp event feed cho subscribers

**Key Methods:**
- `Add(txs, sync)`: Thêm transactions
- `Pending(filter)`: Lấy pending transactions
- `SubscribeTransactions(ch, reorgs)`: Subscribe events

### 2. LegacyPool (`core/txpool/legacypool/legacypool.go`)

**Chức năng:**
- Quản lý EVM transactions (Legacy, EIP-1559, ...)
- Phân loại pending/queued
- Validation và promotion

**Key Methods:**
- `Add(txs, sync)`: Add transactions
- `addTxsLocked(txs)`: Internal add với lock
- `requestPromoteExecutables(accounts)`: Promote queued → pending

### 3. Validation (`core/txpool/validation.go`)

**Chức năng:**
- Validate transaction theo consensus rules
- Validate state-dependent (balance, nonce)
- Check gas, fees, signatures

**Key Functions:**
- `ValidateTransaction()`: Basic validation
- `ValidateTransactionWithState()`: State validation

### 4. Filter System (`eth/filters/`)

**Chức năng:**
- Quản lý WebSocket subscriptions
- Bridge giữa event feed và RPC
- Handle filter queries

**Key Components:**
- `FilterAPI`: RPC API handlers
- `EventSystem`: Event subscription management
- `FilterSystem`: Filter resources

### 5. Miner (`miner/`)

**Chức năng:**
- Lấy transactions từ pool
- Sắp xếp và build block
- Mine/validate block

**Key Components:**
- `worker.go`: Main mining logic
- `ordering.go`: Transaction ordering

---

## 📊 So Sánh Performance

| Bước | Thời Gian | Ghi Chú |
|------|-----------|---------|
| RPC Receive | ~1ms | HTTP/WebSocket receive |
| Validation | ~2-3ms | Signature, nonce, balance checks |
| Add to Pool | ~1ms | Insert vào data structures |
| Event Trigger | ~0.1ms | Event feed broadcast |
| WebSocket Send | ~1ms | Network latency |
| **Total Latency** | **~5-6ms** | Từ khi nhận đến khi script nhận |

---

## 🎯 Tóm Tắt

### Workflow Chính:

1. **Submission**: User → RPC → `SendRawTransaction()`
2. **Validation**: Check signature, nonce, balance, gas
3. **Add to Pool**: Insert vào pending/queued
4. **Event Trigger**: `txFeed.Send(NewTxsEvent)` ⚡
5. **WebSocket Notify**: Broadcast đến subscribers
6. **Mining**: Miner lấy transactions, build block
7. **Removal**: Transactions được remove sau khi mine

### Điểm Quan Trọng:

- ✅ **Event-driven**: Không phải polling, notification ngay lập tức
- ✅ **Low latency**: ~5-6ms từ khi add đến khi nhận
- ✅ **100% success**: Bắt được tất cả transactions (trừ khi reject)
- ✅ **Thread-safe**: Sử dụng locks và channels
- ✅ **Scalable**: Event feed pattern hỗ trợ nhiều subscribers

### Code References:

- RPC Entry: `internal/ethapi/api.go:1648`
- Backend: `eth/api_backend.go:322`
- Main Pool: `core/txpool/txpool.go:314`
- Legacy Pool: `core/txpool/legacypool/legacypool.go:904`
- Validation: `core/txpool/validation.go:61`
- Event Trigger: `core/txpool/legacypool/legacypool.go:1295`
- WebSocket: `eth/filters/api.go:182`
- Mining: `miner/worker.go`, `miner/ordering.go`

---

**Đây là workflow hoàn chỉnh của mempool trong Geth!** 🎉

