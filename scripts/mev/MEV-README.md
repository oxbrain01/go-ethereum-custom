# MEV (Maximal Extractable Value) - Hướng Dẫn Sử Dụng

## 📋 Tổng Quan

Tài liệu này cung cấp hướng dẫn chi tiết về MEV và cách phát hiện các cơ hội MEV trong mempool.

## 📁 Files

1. **`MEV-ANALYSIS.md`**: Phân tích chi tiết về các loại MEV, tiềm năng, và cách thực hiện
2. **`detect-mev-opportunities.js`**: Script phát hiện cơ hội MEV trong mempool (chỉ để giáo dục)

## 🚀 Cách Sử Dụng

### 1. Đọc Tài Liệu Phân Tích

```bash
cat scripts/MEV-ANALYSIS.md
# hoặc mở trong editor
```

### 2. Chạy Script Phát Hiện MEV

**Yêu cầu:**

- Node.js đã cài đặt
- Geth node đang chạy với WebSocket enabled (`--ws`)
- Mempool có transactions

**Chạy script:**

```bash
# Sử dụng default ports (8546 HTTP, 8547 WS)
node scripts/detect-mev-opportunities.js

# Hoặc chỉ định custom ports
WS_URL=ws://localhost:8547 HTTP_URL=http://localhost:8546 node scripts/detect-mev-opportunities.js
```

**Output mẫu:**

```
🔍 MEV Opportunity Detector
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔌 WebSocket: ws://localhost:8547
🌐 HTTP RPC: http://localhost:8546
💡 Monitoring mempool for MEV opportunities...
💡 Press Ctrl+C to stop
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Connected to WebSocket

📡 Subscribed to newPendingTransactions

💡 Waiting for transactions...

================================================================================
🔍 MEV OPPORTUNITY #1 [14:30:45.123]
   Transaction: 0x1234...abcd
   ----------------------------------------------------------------------------

   📊 Type: SANDWICH
   💰 Estimated Profit: 0.001500 ETH (~$3.00)
   📈 Confidence: 50%
   📋 Details:
      - userAmount: 10.000000
      - frontRunAmount: 5.000000
      - priceImpact: 0.005000
      - gasCost: 0.000630

   ⚠️  NOTE: This is for educational purposes only!
   ⚠️  Do not automatically execute MEV without proper authorization!
================================================================================
```

## 🎯 Các Loại MEV Được Phát Hiện

Script này phát hiện **TẤT CẢ 6 loại MEV chính** có tiềm năng take profit:

1. **Arbitrage**: Chênh lệch giá giữa các DEX
2. **Sandwich Attacks**: Tấn công kẹp các swap lớn
3. **Front-Running**: Chạy trước các transactions có lợi
4. **Back-Running**: Chạy sau các transactions lớn để hưởng lợi từ price recovery
5. **Liquidations**: Thanh lý các vị thế cho vay
6. **JIT Liquidity**: Thêm liquidity trước swap lớn, remove sau để lấy fees

## ⚙️ Cấu Hình

### Thay Đổi Ngưỡng Lợi Nhuận Tối Thiểu

Chỉnh sửa trong `detect-mev-opportunities.js`:

```javascript
const MIN_PROFIT_THRESHOLDS = {
  [MEV_TYPES.ARBITRAGE]: 0.001, // 0.001 ETH
  [MEV_TYPES.LIQUIDATION]: 0.01, // 0.01 ETH
  [MEV_TYPES.SANDWICH]: 0.0005, // 0.0005 ETH
  [MEV_TYPES.FRONT_RUN]: 0.005, // 0.005 ETH
  // ...
};
```

### Thêm DEX Addresses

Để phát hiện swap transactions chính xác hơn, thêm DEX addresses:

```javascript
const dexAddresses = [
  "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // Uniswap V2 Router
  "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F", // Sushiswap Router
  // Thêm các DEX khác
];
```

## 📊 Hiểu Kết Quả

### Profit Estimation

- **Estimated Profit**: Lợi nhuận ước tính sau khi trừ gas cost
- **Confidence**: Độ tin cậy của cơ hội (0-100%)
- **Details**: Chi tiết về cơ hội (amount, price impact, gas cost, etc.)

### Confidence Levels

- **High (60-90%)**: Cơ hội rõ ràng, ít cạnh tranh
- **Medium (40-60%)**: Cơ hội tốt, cạnh tranh trung bình
- **Low (20-40%)**: Cơ hội có thể, cạnh tranh cao

## ⚠️ Lưu Ý Quan Trọng

1. **CHỈ DÙNG CHO MỤC ĐÍCH GIÁO DỤC**: Script này chỉ phát hiện cơ hội, không tự động thực hiện MEV

2. **KHÔNG TỰ ĐỘNG EXECUTE**: Việc tự động thực hiện MEV có thể:

   - Vi phạm quy định
   - Gây thiệt hại cho người dùng
   - Bị coi là market manipulation

3. **RISK WARNING**: MEV có rủi ro cao:

   - Gas wars có thể làm giảm profit
   - Transactions có thể fail
   - Competition từ các bot khác

4. **LEGAL CONSIDERATIONS**: Một số loại MEV có thể bị coi là illegal ở một số quốc gia

## 🔧 Troubleshooting

### Script không kết nối được WebSocket

**Lỗi:**

```
❌ WebSocket error: connect ECONNREFUSED
```

**Giải pháp:**

- Kiểm tra Geth có đang chạy không: `ps aux | grep geth`
- Kiểm tra WebSocket có được enable không: `--ws` flag
- Kiểm tra port: Mặc định là 8547

### Không phát hiện được MEV opportunities

**Nguyên nhân:**

- Mempool không có transactions phù hợp
- Ngưỡng profit quá cao
- DEX addresses chưa được cấu hình đúng

**Giải pháp:**

- Giảm `MIN_PROFIT_THRESHOLDS`
- Thêm nhiều DEX addresses
- Gửi test transactions vào mempool

### Script chạy chậm

**Nguyên nhân:**

- Quá nhiều transactions trong mempool
- RPC calls mất thời gian

**Giải pháp:**

- Tối ưu hóa RPC calls
- Sử dụng batch requests
- Cache kết quả khi có thể

## 🛡️ MEV Protection

Để bảo vệ khỏi MEV, xem tài liệu chi tiết:

```bash
cat scripts/MEV-PROTECTION.md
```

**Quick Protection Tips:**

1. **Slippage Protection**: Luôn set max slippage 0.5-1% cho small swaps
2. **Private Mempools**: Sử dụng Flashbots Protect cho large transactions
3. **Split Swaps**: Chia nhỏ large swaps thành nhiều small swaps
4. **Health Factor**: Giữ health factor > 1.5 cho lending positions
5. **DEX Aggregators**: Sử dụng 1inch, Paraswap để tự động optimize

**Run Protection Examples:**

```bash
node scripts/mev-protection-examples.js
```

## 📚 Tài Liệu Tham Khảo

- **MEV-ANALYSIS.md**: Phân tích chi tiết về MEV
- **MEV-PROTECTION.md**: Hướng dẫn bảo vệ khỏi MEV (⚠️ QUAN TRỌNG)
- **mev-protection-examples.js**: Code examples cho MEV protection
- **MEMPOOL-WORKFLOW.md**: Hiểu workflow của mempool
- [Flashbots Documentation](https://docs.flashbots.net/)
- [Ethereum.org MEV Guide](https://ethereum.org/en/developers/docs/mev/)

## 🔗 Related Scripts

- `watch-mempool-nodejs.js`: Monitor mempool real-time
- `start-production-like-blockchain.sh`: Start local blockchain để test

## 💡 Tips

1. **Test trên Local Blockchain**: Sử dụng local blockchain để test mà không risk real money
2. **Monitor Gas Prices**: Gas price cao có thể làm giảm profit
3. **Understand Slippage**: Slippage có thể ảnh hưởng lớn đến profit
4. **Capital Requirements**: Một số loại MEV cần vốn lớn (hoặc flash loans)

## 🎓 Học Thêm

Để hiểu sâu hơn về MEV:

1. Đọc `MEV-ANALYSIS.md` để hiểu từng loại MEV
2. Xem code trong `miner/ordering.go` để hiểu transaction ordering
3. Thử nghiệm với script `detect-mev-opportunities.js`
4. Tìm hiểu về Flashbots và MEV-Boost

---

**Disclaimer**: Tài liệu này chỉ dùng cho mục đích giáo dục. Việc thực hiện MEV có thể có rủi ro pháp lý và tài chính. Hãy tự chịu trách nhiệm khi sử dụng.
