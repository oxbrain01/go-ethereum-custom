# MEV Protection - Hướng Dẫn Bảo Vệ Khỏi Tất Cả Các Loại MEV

## 📋 Tổng Quan

Tài liệu này cung cấp hướng dẫn chi tiết về cách bảo vệ khỏi **TẤT CẢ 6 loại MEV** có tiềm năng take profit:

1. **Arbitrage** - Chênh lệch giá giữa các DEX
2. **Sandwich Attacks** - Tấn công kẹp các swap lớn
3. **Front-Running** - Chạy trước các transactions có lợi
4. **Back-Running** - Chạy sau để hưởng lợi từ price recovery
5. **Liquidations** - Thanh lý các vị thế cho vay
6. **JIT Liquidity** - Thêm liquidity trước swap, remove sau

---

## 🛡️ 1. Protection Against Arbitrage

### Vấn Đề

Arbitrage bots khai thác chênh lệch giá giữa các DEX, làm giảm lợi nhuận của liquidity providers.

### Giải Pháp

#### A. Sử Dụng Private Mempools

**Flashbots Protect** hoặc **MEV-Boost** để gửi transactions qua private relay:

```javascript
// Sử dụng Flashbots Protect RPC
const flashbotsRpc = "https://rpc.flashbots.net";

async function sendProtectedTransaction(tx) {
  // Gửi transaction qua Flashbots Protect
  // Transaction sẽ không xuất hiện trong public mempool
  const response = await fetch(flashbotsRpc, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      jsonrpc: "2.0",
      method: "eth_sendRawTransaction",
      params: [tx],
      id: 1,
    }),
  });
  return response.json();
}
```

#### B. Sử Dụng Time-Weighted Average Price (TWAP)

Thay vì dùng spot price, sử dụng TWAP để giảm arbitrage opportunities:

```solidity
// Uniswap V3 TWAP Oracle
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract TWAPOracle {
    IUniswapV3Pool public pool;

    function getTWAP(uint32 secondsAgo) external view returns (uint256) {
        // Get time-weighted average price
        // Reduces arbitrage opportunities
        return pool.observe(secondsAgo);
    }
}
```

#### C. Batch Transactions

Gửi nhiều transactions cùng lúc để giảm time window cho arbitrage:

```javascript
// Batch multiple swaps in one transaction
async function batchSwap(swaps) {
  const batchTx = {
    to: dexRouter,
    data: encodeBatchSwap(swaps), // Encode multiple swaps
    gasPrice: await getCurrentGasPrice(),
  };

  // Send as single transaction
  await sendTransaction(batchTx);
}
```

---

## 🛡️ 2. Protection Against Sandwich Attacks

### Vấn Đề

Sandwich attacks kẹp swap của bạn giữa front-run và back-run, làm bạn mất tiền do slippage.

### Giải Pháp

#### A. Sử Dụng Slippage Protection

**Luôn set max slippage tolerance thấp:**

```javascript
// MetaMask example
const swapTx = {
  to: uniswapRouter,
  data: encodeSwap(tokenIn, tokenOut, amount, minAmountOut),
  // minAmountOut = amount * (1 - maxSlippage)
  // Ví dụ: maxSlippage = 0.5% → minAmountOut = amount * 0.995
};

// Nếu price impact > maxSlippage, transaction sẽ revert
```

**Best Practice:**

- **Small swaps (< $1,000)**: Max slippage 0.5%
- **Medium swaps ($1,000 - $10,000)**: Max slippage 1%
- **Large swaps (> $10,000)**: Max slippage 2-3%

#### B. Sử Dụng Private Mempools

Gửi transaction qua Flashbots Protect để tránh public mempool:

```javascript
// Flashbots Protect
const protectedTx = await flashbotsProtect.sendTransaction({
  transaction: swapTx,
  // Transaction không xuất hiện trong public mempool
  // Bots không thể detect để sandwich
});
```

#### C. Split Large Swaps

Chia nhỏ swap lớn thành nhiều swap nhỏ:

```javascript
async function splitSwap(amount, numSplits = 5) {
  const splitAmount = amount / numSplits;
  const swaps = [];

  for (let i = 0; i < numSplits; i++) {
    swaps.push({
      amount: splitAmount,
      delay: i * 1000, // 1 second between swaps
    });
  }

  // Execute swaps sequentially
  for (const swap of swaps) {
    await new Promise((resolve) => setTimeout(resolve, swap.delay));
    await executeSwap(swap.amount);
  }
}
```

#### D. Sử Dụng DEX Aggregators

DEX aggregators (1inch, Paraswap, etc.) tự động tìm best route và split orders:

```javascript
// 1inch API
const quote = await fetch(
  `https://api.1inch.io/v5.0/1/quote?fromTokenAddress=${tokenIn}&toTokenAddress=${tokenOut}&amount=${amount}`
);

// 1inch tự động:
// - Tìm best route across multiple DEXs
// - Split orders to reduce price impact
// - Optimize gas costs
```

---

## 🛡️ 3. Protection Against Front-Running

### Vấn Đề

Front-runners chạy trước transaction của bạn để hưởng lợi (NFT sniping, token launches, etc.).

### Giải Pháp

#### A. Sử Dụng Commit-Reveal Scheme

Gửi transaction với hash trước, reveal sau:

```solidity
contract CommitReveal {
    mapping(address => bytes32) public commits;

    // Step 1: Commit (send hash)
    function commit(bytes32 hash) external {
        commits[msg.sender] = hash;
    }

    // Step 2: Reveal (after some blocks)
    function reveal(
        uint256 nonce,
        address target,
        bytes calldata data
    ) external {
        bytes32 hash = keccak256(abi.encodePacked(nonce, target, data));
        require(commits[msg.sender] == hash, "Invalid reveal");

        // Execute transaction
        (bool success, ) = target.call(data);
        require(success, "Call failed");
    }
}
```

#### B. Sử Dụng Private Mempools

Gửi transaction qua private relay:

```javascript
// Flashbots Protect hoặc MEV-Boost
const privateTx = await flashbots.sendBundle({
  transactions: [yourTransaction],
  // Transaction không xuất hiện trong public mempool
  // Front-runners không thể detect
});
```

#### C. Sử Dụng Time-Locked Transactions

Delay execution để front-runners không biết khi nào execute:

```solidity
contract TimeLocked {
    mapping(bytes32 => uint256) public executionTime;

    function schedule(
        address target,
        bytes calldata data,
        uint256 delay
    ) external returns (bytes32 txHash) {
        txHash = keccak256(abi.encodePacked(target, data, block.timestamp));
        executionTime[txHash] = block.timestamp + delay;
    }

    function execute(
        address target,
        bytes calldata data
    ) external {
        bytes32 txHash = keccak256(abi.encodePacked(target, data, block.timestamp - delay));
        require(block.timestamp >= executionTime[txHash], "Too early");
        // Execute...
    }
}
```

#### D. Sử Dụng Gas Price Limits

Set gas price thấp để transaction không được include ngay:

```javascript
// Set gas price thấp để delay execution
const tx = {
  ...yourTransaction,
  gasPrice: (await getCurrentGasPrice()) * 0.5, // 50% of current gas
  // Transaction sẽ chờ đến khi gas price giảm
  // Front-runners không biết khi nào sẽ execute
};
```

---

## 🛡️ 4. Protection Against Back-Running

### Vấn Đề

Back-runners chạy sau transaction của bạn để hưởng lợi từ price recovery.

### Giải Pháp

#### A. Sử Dụng Slippage Protection

Tương tự như sandwich protection, set max slippage thấp:

```javascript
const swapTx = {
    ...yourSwap,
    minAmountOut: calculateMinAmountOut(amount, maxSlippage = 0.5%),
    // Nếu price recovery quá nhanh, transaction sẽ revert
};
```

#### B. Sử Dụng Batch Transactions

Execute nhiều transactions trong cùng block để giảm time window:

```javascript
// Execute multiple swaps in same block
const batchTx = {
  to: batchRouter,
  data: encodeBatch([swap1, swap2, swap3]),
};

// All execute in same block → no time for back-running
```

#### C. Sử Dụng Flash Loans

Sử dụng flash loans để execute atomic operations:

```solidity
contract FlashLoanProtection {
    function executeWithFlashLoan(
        address token,
        uint256 amount,
        bytes calldata callbackData
    ) external {
        // Borrow flash loan
        IERC3156FlashLender lender = IERC3156FlashLender(lenderAddress);
        lender.flashLoan(
            IERC3156FlashBorrower(address(this)),
            token,
            amount,
            callbackData
        );
    }

    function onFlashLoan(
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32) {
        // Execute your operation atomically
        // No time for back-running

        // Repay flash loan
        IERC20(token).transfer(msg.sender, amount + fee);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
```

---

## 🛡️ 5. Protection Against Liquidations

### Vấn Đề

Liquidation bots thanh lý position của bạn ngay khi health factor < 1.0.

### Giải Pháp

#### A. Maintain Healthy Collateral Ratio

**Luôn giữ health factor > 1.5:**

```javascript
// Monitor health factor
async function monitorHealthFactor(position) {
  const healthFactor = calculateHealthFactor(position);

  if (healthFactor < 1.5) {
    // Add more collateral hoặc repay debt
    await addCollateral(position);
  }
}
```

**Best Practice:**

- **Safe**: Health factor > 2.0
- **Warning**: Health factor 1.5 - 2.0
- **Danger**: Health factor < 1.5
- **Liquidation Risk**: Health factor < 1.1

#### B. Sử Dụng Price Alerts

Set alerts khi giá collateral giảm:

```javascript
// Price alert system
const priceAlert = {
  token: "ETH",
  currentPrice: 2000,
  alertPrice: 1900, // Alert when price drops 5%
  action: async () => {
    // Add collateral or repay debt
    await protectPosition();
  },
};
```

#### C. Sử Dụng Stable Collateral

Sử dụng stablecoins làm collateral để giảm volatility:

```javascript
// Use stablecoins as collateral
const stableCollaterals = [
  "USDC", // USD Coin
  "USDT", // Tether
  "DAI", // Dai Stablecoin
];

// Avoid volatile collaterals
const volatileCollaterals = [
  "ETH", // High volatility
  "BTC", // High volatility
];
```

#### D. Auto-Repay System

Tự động repay debt khi health factor thấp:

```solidity
contract AutoRepay {
    function checkAndRepay(address user) external {
        uint256 healthFactor = calculateHealthFactor(user);

        if (healthFactor < 1.2) {
            // Automatically repay some debt
            uint256 repayAmount = calculateRepayAmount(user);
            repayDebt(user, repayAmount);
        }
    }
}
```

---

## 🛡️ 6. Protection Against JIT Liquidity

### Vấn Đề

JIT liquidity providers thêm liquidity trước swap của bạn, remove sau để lấy fees.

### Giải Pháp

#### A. Sử Dụng Existing Liquidity Pools

Chỉ swap trong pools đã có liquidity sẵn:

```javascript
// Check pool liquidity before swapping
async function checkPoolLiquidity(poolAddress) {
  const pool = await getPoolInfo(poolAddress);

  // Only swap if pool has sufficient existing liquidity
  if (pool.liquidity < MIN_LIQUIDITY) {
    throw new Error("Pool liquidity too low - JIT risk");
  }

  return pool;
}
```

#### B. Sử Dụng TWAP-Based Pricing

Sử dụng TWAP thay vì spot price:

```solidity
// Use TWAP oracle instead of spot price
contract TWAPSwap {
    IUniswapV3Pool public pool;

    function swapWithTWAP(
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) external {
        // Get TWAP price (time-weighted average)
        uint256 twapPrice = pool.observe(3600); // 1 hour TWAP

        // Calculate min amount out based on TWAP
        uint256 minAmountOut = (amount * twapPrice) / 1e18;

        // Execute swap
        // JIT providers can't manipulate TWAP easily
    }
}
```

#### C. Sử Dụng DEX Aggregators

DEX aggregators tự động tìm best route và tránh JIT pools:

```javascript
// 1inch automatically avoids JIT liquidity
const swap = await oneinch.swap({
  fromToken: tokenIn,
  toToken: tokenOut,
  amount: amount,
  // 1inch will:
  // - Avoid pools with recent liquidity additions
  // - Use pools with established liquidity
  // - Split across multiple pools
});
```

#### D. Monitor Pool Changes

Monitor liquidity changes trước khi swap:

```javascript
// Monitor pool liquidity changes
async function monitorPoolBeforeSwap(poolAddress, delay = 60) {
  const initialLiquidity = await getPoolLiquidity(poolAddress);

  // Wait and check again
  await new Promise((resolve) => setTimeout(resolve, delay * 1000));

  const currentLiquidity = await getPoolLiquidity(poolAddress);

  // If liquidity increased significantly, might be JIT
  if (currentLiquidity > initialLiquidity * 1.1) {
    console.warn("Possible JIT liquidity detected");
    // Consider using different pool or delaying swap
  }
}
```

---

## 🔧 Technical Implementation

### 1. Flashbots Protect Integration

```javascript
// Install: npm install @flashbots/ethers-provider-bundle
const {
  FlashbotsBundleProvider,
} = require("@flashbots/ethers-provider-bundle");
const { ethers } = require("ethers");

async function sendProtectedTransaction(signer, transaction) {
  const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
  const flashbotsProvider = await FlashbotsBundleProvider.create(
    provider,
    signer
  );

  // Create bundle
  const bundle = [
    {
      transaction,
      signer,
    },
  ];

  // Send bundle to Flashbots
  const bundleResponse = await flashbotsProvider.sendBundle(
    bundle,
    (await provider.getBlockNumber()) + 1
  );

  return bundleResponse;
}
```

### 2. MEV-Boost Integration

```javascript
// MEV-Boost for validators
// Validators can use MEV-Boost to outsource block building
// This reduces MEV extraction by validators

// For users: Use MEV-Boost compatible RPC
const mevBoostRpc = "https://mainnet.mev-boost.flashbots.net";

async function sendMevBoostTransaction(tx) {
  // Send transaction via MEV-Boost
  // Transaction will be included in block by MEV-Boost builder
  // More fair distribution of MEV
}
```

### 3. Slippage Protection Wrapper

```javascript
// Wrapper function with automatic slippage protection
async function protectedSwap(
  tokenIn,
  tokenOut,
  amount,
  maxSlippage = 0.005 // 0.5% default
) {
  // Get current price
  const currentPrice = await getPrice(tokenIn, tokenOut);

  // Calculate min amount out
  const minAmountOut = amount * currentPrice * (1 - maxSlippage);

  // Build swap transaction
  const swapTx = {
    to: uniswapRouter,
    data: encodeSwap(tokenIn, tokenOut, amount, minAmountOut),
    gasPrice: await getCurrentGasPrice(),
  };

  // Send via Flashbots Protect if large swap
  if (amount > LARGE_SWAP_THRESHOLD) {
    return await sendProtectedTransaction(swapTx);
  }

  return await sendTransaction(swapTx);
}
```

### 4. Health Factor Monitor

```javascript
// Monitor lending position health factor
class HealthFactorMonitor {
  constructor(protocol, userAddress) {
    this.protocol = protocol;
    this.userAddress = userAddress;
  }

  async checkHealthFactor() {
    const position = await this.protocol.getPosition(this.userAddress);
    const healthFactor = this.calculateHealthFactor(position);

    if (healthFactor < 1.5) {
      await this.alertUser(healthFactor);
    }

    if (healthFactor < 1.1) {
      await this.autoProtect(position);
    }

    return healthFactor;
  }

  async autoProtect(position) {
    // Automatically add collateral or repay debt
    const repayAmount = this.calculateRepayAmount(position);
    await this.protocol.repayDebt(this.userAddress, repayAmount);
  }
}
```

---

## 📊 Best Practices Summary

### For Users

1. **Always Use Slippage Protection**

   - Set max slippage 0.5-1% for small swaps
   - Set max slippage 2-3% for large swaps

2. **Use Private Mempools for Large Transactions**

   - Flashbots Protect for swaps > $10,000
   - MEV-Boost compatible RPC

3. **Split Large Swaps**

   - Break large swaps into smaller chunks
   - Execute with delays between chunks

4. **Monitor Health Factors**

   - Keep health factor > 1.5 for lending positions
   - Set up price alerts

5. **Use DEX Aggregators**
   - 1inch, Paraswap, etc. automatically optimize routes
   - Reduce price impact and MEV exposure

### For Developers

1. **Implement Commit-Reveal Schemes**

   - For sensitive operations (NFT mints, token launches)

2. **Use TWAP Oracles**

   - Instead of spot prices
   - Reduces arbitrage and JIT opportunities

3. **Batch Transactions**

   - Execute multiple operations atomically
   - Reduces time window for MEV

4. **Monitor Mempool**

   - Detect suspicious transactions
   - Implement rate limiting

5. **Use Flash Loans**
   - For atomic operations
   - Reduces back-running opportunities

---

## 🛠️ Tools & Services

### 1. Flashbots Protect

- **URL**: https://protect.flashbots.net
- **Use Case**: Private mempool for transactions
- **Cost**: Free

### 2. MEV-Boost

- **URL**: https://boost.flashbots.net
- **Use Case**: Fair MEV distribution for validators
- **Cost**: Free

### 3. 1inch Aggregator

- **URL**: https://1inch.io
- **Use Case**: Best route finding, split orders
- **Cost**: Free (small fee on swaps)

### 4. Paraswap

- **URL**: https://paraswap.io
- **Use Case**: DEX aggregation, MEV protection
- **Cost**: Free (small fee on swaps)

### 5. OpenMEV

- **URL**: https://openmev.org
- **Use Case**: MEV protection for DeFi protocols
- **Cost**: Varies

---

## 📚 References

- [Flashbots Documentation](https://docs.flashbots.net/)
- [MEV-Boost Specification](https://ethereum.org/en/developers/docs/mev/)
- [Ethereum.org MEV Guide](https://ethereum.org/en/developers/docs/mev/)
- [1inch Documentation](https://docs.1inch.io/)
- [Paraswap Documentation](https://developers.paraswap.network/)

---

## 🔗 Related Files

- `scripts/MEV-ANALYSIS.md`: Phân tích chi tiết về MEV
- `scripts/detect-mev-opportunities.js`: Script phát hiện MEV opportunities
- `scripts/MEV-README.md`: Hướng dẫn sử dụng MEV detector

---

## ⚠️ Important Notes

1. **No 100% Protection**: Không có cách nào bảo vệ 100% khỏi MEV
2. **Trade-offs**: Mỗi giải pháp đều có trade-offs (gas cost, complexity, etc.)
3. **Stay Updated**: MEV landscape thay đổi nhanh, cần cập nhật thường xuyên
4. **Test First**: Luôn test trên testnet trước khi deploy lên mainnet

---

**Disclaimer**: Tài liệu này chỉ dùng cho mục đích giáo dục. Hãy tự chịu trách nhiệm khi implement các giải pháp bảo vệ MEV.
