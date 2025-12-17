#!/usr/bin/env node
/**
 * MEV Opportunity Detector - Tổng Hợp Đầy Đủ Các Loại MEV
 *
 * Script này phát hiện và phân tích TẤT CẢ các loại MEV có tiềm năng take profit:
 *
 * ✅ 1. ARBITRAGE - Chênh lệch giá giữa các DEX
 * ✅ 2. SANDWICH - Tấn công kẹp các swap lớn
 * ✅ 3. FRONT_RUN - Chạy trước các transactions có lợi
 * ✅ 4. BACK_RUN - Chạy sau để hưởng lợi từ price recovery
 * ✅ 5. LIQUIDATION - Thanh lý các vị thế cho vay
 * ✅ 6. JIT_LIQUIDITY - Thêm liquidity trước swap, remove sau để lấy fees
 *
 * CHỈ DÙNG CHO MỤC ĐÍCH GIÁO DỤC - KHÔNG TỰ ĐỘNG THỰC HIỆN MEV
 *
 * Usage: node detect-mev-opportunities.js
 *
 * Total Estimated Annual MEV: $430M - $2.15B+
 *
 * Reference: scripts/MEV-ANALYSIS.md for detailed analysis
 */

const WebSocket = require("ws");
const http = require("http");

const WS_URL = process.env.WS_URL || "ws://localhost:8547";
const HTTP_URL = process.env.HTTP_URL || "http://localhost:8546";

// MEV opportunity types
const MEV_TYPES = {
  ARBITRAGE: "ARBITRAGE",
  LIQUIDATION: "LIQUIDATION",
  SANDWICH: "SANDWICH",
  FRONT_RUN: "FRONT_RUN",
  BACK_RUN: "BACK_RUN",
  JIT_LIQUIDITY: "JIT_LIQUIDITY",
};

// Minimum profit thresholds (in ETH)
// Lowered for testing - adjust based on your network
const MIN_PROFIT_THRESHOLDS = {
  [MEV_TYPES.ARBITRAGE]: 0.00001, // 0.00001 ETH (lowered from 0.001)
  [MEV_TYPES.LIQUIDATION]: 0.0001, // 0.0001 ETH (lowered from 0.01)
  [MEV_TYPES.SANDWICH]: 0.00001, // 0.00001 ETH (lowered from 0.0005)
  [MEV_TYPES.FRONT_RUN]: 0.0001, // 0.0001 ETH (lowered from 0.005)
  [MEV_TYPES.BACK_RUN]: 0.00001, // 0.00001 ETH (lowered from 0.001)
  [MEV_TYPES.JIT_LIQUIDITY]: 0.0001, // 0.0001 ETH (lowered from 0.01)
};

// Enable debug logging
const DEBUG = process.env.DEBUG === "true" || process.env.DEBUG === "1";
// Show all transactions (even if no MEV opportunity)
const SHOW_ALL_TXS =
  process.env.SHOW_ALL === "true" || process.env.SHOW_ALL === "1";

let opportunityCount = 0;
let transactionCount = 0;
let swapCount = 0;
let ethTransferCount = 0;
let unknownTxCount = 0;

/**
 * Make HTTP RPC call
 */
function rpcCall(method, params = []) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify({
      jsonrpc: "2.0",
      method,
      params,
      id: 1,
    });

    const options = {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": data.length,
      },
    };

    const req = http.request(HTTP_URL, options, (res) => {
      let body = "";
      res.on("data", (chunk) => {
        body += chunk;
      });
      res.on("end", () => {
        try {
          const result = JSON.parse(body);
          if (result.error) {
            reject(new Error(result.error.message));
          } else {
            resolve(result.result);
          }
        } catch (e) {
          reject(e);
        }
      });
    });

    req.on("error", reject);
    req.write(data);
    req.end();
  });
}

/**
 * Get transaction details
 */
async function getTransaction(txHash) {
  return await rpcCall("eth_getTransactionByHash", [txHash]);
}

/**
 * Get transaction receipt
 */
async function getTransactionReceipt(txHash) {
  return await rpcCall("eth_getTransactionReceipt", [txHash]);
}

/**
 * Get current gas price
 */
async function getCurrentGasPrice() {
  const gasPriceHex = await rpcCall("eth_gasPrice", []);
  return parseInt(gasPriceHex, 16);
}

/**
 * Get current block number
 */
async function getCurrentBlockNumber() {
  const blockNumberHex = await rpcCall("eth_blockNumber", []);
  return parseInt(blockNumberHex, 16);
}

/**
 * Get mempool status
 */
async function getMempoolStatus() {
  try {
    const result = await rpcCall("txpool_status", []);
    return {
      pending: parseInt(result.pending, 16),
      queued: parseInt(result.queued, 16),
    };
  } catch (e) {
    return { pending: 0, queued: 0 };
  }
}

/**
 * Get mempool content
 */
async function getMempoolContent() {
  try {
    return await rpcCall("txpool_content", []);
  } catch (e) {
    return { pending: {}, queued: {} };
  }
}

/**
 * Common DEX swap function signatures (first 4 bytes of keccak256)
 */
const SWAP_FUNCTION_SIGNATURES = {
  // Uniswap V2
  swapExactETHForTokens: "0x7ff36ab5",
  swapETHForExactTokens: "0x4a25d94a",
  swapExactTokensForETH: "0x18cbafe5",
  swapTokensForExactETH: "0x4a25d94a",
  swapExactTokensForTokens: "0x38ed1739",
  swapTokensForExactTokens: "0x8803dbee",
  // Uniswap V3
  exactInputSingle: "0x414bf389",
  exactInput: "0xc04b8d59",
  exactOutputSingle: "0xdb3e2198",
  exactOutput: "0xf28c0498",
  // Generic swap
  swap: "0x022c0d9f",
  // Add more as needed
};

/**
 * Check if transaction is a simple ETH transfer (no input data or empty input)
 */
function isETHTransfer(tx) {
  if (!tx) return false;
  // ETH transfer: has value > 0 and (no input data OR input is just "0x" OR input is "0x")
  const hasValue = tx.value && parseInt(tx.value, 16) > 0;
  const hasNoInput = !tx.input || tx.input === "0x" || tx.input.length <= 2;
  return hasValue && hasNoInput;
}

/**
 * Check if transaction is a swap by analyzing input data
 * @param {Object} tx - Transaction object
 * @param {boolean} incrementCount - Whether to increment swapCount (default: false to avoid double-counting)
 */
function isSwapTransaction(tx, incrementCount = false) {
  if (!tx || !tx.input || tx.input.length < 10) return false;

  // Check if input data starts with a known swap function signature
  const inputPrefix = tx.input.toLowerCase().substring(0, 10); // 0x + 4 bytes = 10 chars

  const isSwap = Object.values(SWAP_FUNCTION_SIGNATURES).some(
    (sig) => inputPrefix === sig.toLowerCase()
  );

  if (isSwap && incrementCount) {
    swapCount++;
    if (DEBUG) {
      console.log(`   🔄 Detected swap function: ${inputPrefix}`);
    }
  }

  return isSwap;
}

/**
 * Check if transaction targets known DEX router (optional, for additional filtering)
 */
function isKnownDEXRouter(tx) {
  if (!tx || !tx.to) return false;

  // Common DEX contract addresses (Mainnet - adjust for your network)
  // Note: On testnet/local, these addresses might not exist
  // So we primarily rely on function signature detection
  const dexAddresses = [
    "0x7a250d5630b4cf539739df2c5dacb4c659f2488d", // Uniswap V2 Router
    "0xd9e1ce17f2641f24ae83637ab66a2cca9c378b9f", // Sushiswap Router
    "0xe592427a0aece92de3edee1f18e0157c05861564", // Uniswap V3 Router
    // Add more DEX addresses as needed
  ];

  return dexAddresses.includes(tx.to.toLowerCase());
}

/**
 * Common liquidation function signatures
 */
const LIQUIDATION_FUNCTION_SIGNATURES = {
  liquidateBorrow: "0x2986c0e5",
  liquidationCall: "0xea8a1af0",
  liquidate: "0xdb005a1c",
  // Add more as needed
};

/**
 * Check if transaction is a liquidation by analyzing input data
 */
function isLiquidationTransaction(tx) {
  if (!tx || !tx.input) return false;

  // Check if input data starts with a known liquidation function signature
  const inputPrefix = tx.input.toLowerCase().substring(0, 10);

  const isLiquidation = Object.values(LIQUIDATION_FUNCTION_SIGNATURES).some(
    (sig) => inputPrefix === sig.toLowerCase()
  );

  if (DEBUG && isLiquidation) {
    console.log(`   💧 Detected liquidation function: ${inputPrefix}`);
  }

  return isLiquidation;
}

/**
 * Check if transaction targets known lending protocol (optional)
 */
function isKnownLendingProtocol(tx) {
  if (!tx || !tx.to) return false;

  // Common lending protocol addresses (Mainnet - adjust for your network)
  const lendingProtocols = [
    "0x7d2768de32b0b80b7a3454c06bdac94a69ddc7a9", // Aave Lending Pool
    "0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b", // Compound Comptroller
    // Add more protocol addresses as needed
  ];

  return lendingProtocols.includes(tx.to.toLowerCase());
}

/**
 * Parse swap amount from transaction
 * Tries multiple methods:
 * 1. tx.value (for ETH swaps)
 * 2. Extract from input data (for token swaps)
 */
function parseSwapAmount(tx) {
  if (!tx) return 0;

  // Method 1: Check tx.value (for ETH swaps like swapExactETHForTokens)
  if (tx.value) {
    const ethValue = parseInt(tx.value, 16) / 1e18;
    if (ethValue > 0) {
      if (DEBUG) {
        console.log(`   💰 Found ETH value: ${ethValue} ETH`);
      }
      return ethValue;
    }
  }

  // Method 2: Try to extract amount from input data
  // This is simplified - in production you'd properly decode ABI
  if (tx.input && tx.input.length >= 138) {
    // Most swap functions have amount as first or second parameter (32 bytes = 64 hex chars)
    // Skip function selector (10 chars) and try to parse amount
    try {
      // For swapExactTokensForETH, amountIn is at position 10-74 (32 bytes)
      // For swapExactETHForTokens, amountOutMin is at position 10-74, but amount is in value
      // This is a heuristic - proper decoding would use ABI
      const amountHex = "0x" + tx.input.substring(10, 74); // First parameter after selector
      const amount = parseInt(amountHex, 16);

      // If amount looks reasonable (not zero, not too large), use it
      if (amount > 0 && amount < 1e30) {
        // Assume 18 decimals for tokens (convert to ETH equivalent for display)
        const tokenAmount = amount / 1e18;
        if (tokenAmount > 0.000001 && tokenAmount < 1000000) {
          if (DEBUG) {
            console.log(
              `   💰 Extracted amount from input: ${tokenAmount} (token units)`
            );
          }
          // Return as ETH equivalent for profit calculation
          // In production, you'd convert using actual token prices
          return tokenAmount * 0.001; // Rough estimate: assume token ~$0.001 ETH equivalent
        }
      }
    } catch (e) {
      // Ignore parsing errors
    }
  }

  // Method 3: If no value and can't parse input, return 0
  // But don't reject the transaction - let other checks decide
  return 0;
}

/**
 * Get minimum meaningful amount threshold based on transaction type
 */
function getMinimumAmount(mevType) {
  switch (mevType) {
    case MEV_TYPES.ARBITRAGE:
      return 0.001; // 0.001 ETH equivalent
    case MEV_TYPES.SANDWICH:
      return 0.01; // 0.01 ETH equivalent
    case MEV_TYPES.FRONT_RUN:
      return 0.01; // 0.01 ETH equivalent
    case MEV_TYPES.BACK_RUN:
      return 0.01; // 0.01 ETH equivalent
    case MEV_TYPES.LIQUIDATION:
      return 0.001; // 0.001 ETH equivalent
    case MEV_TYPES.JIT_LIQUIDITY:
      return 0.1; // 0.1 ETH equivalent
    default:
      return 0.001;
  }
}

/**
 * Estimate gas cost
 */
function estimateGasCost(gasPrice, gasLimit = 21000) {
  return (gasPrice * gasLimit) / 1e18; // Convert to ETH
}

/**
 * Detect Arbitrage Opportunity
 */
async function detectArbitrage(tx) {
  // This is a simplified example
  // In reality, you would:
  // 1. Monitor prices across multiple DEXs
  // 2. Calculate price differences
  // 3. Estimate profit after gas costs

  if (!isSwapTransaction(tx)) return null;

  const amount = parseSwapAmount(tx);
  const minAmount = getMinimumAmount(MEV_TYPES.ARBITRAGE);

  if (DEBUG) {
    console.log(`   🔍 Arbitrage check: amount=${amount}, min=${minAmount}`);
  }

  // Lower threshold for testing - accept any swap with value
  if (amount < minAmount && amount === 0) return null; // Only reject if truly zero

  // Simulated arbitrage detection
  // In production, you would query actual DEX prices
  const simulatedPriceDiff = 0.001; // 0.1% price difference
  // Use minimum amount if parsed amount is too small
  const effectiveAmount = amount > 0 ? amount : minAmount;
  const estimatedProfit = effectiveAmount * simulatedPriceDiff;
  const gasPrice = await getCurrentGasPrice();
  const gasCost = estimateGasCost(gasPrice, 150000); // ~150k gas for arbitrage
  const netProfit = estimatedProfit - gasCost;

  if (netProfit > MIN_PROFIT_THRESHOLDS[MEV_TYPES.ARBITRAGE]) {
    return {
      type: MEV_TYPES.ARBITRAGE,
      profit: netProfit,
      confidence: 0.6, // 60% confidence (simulated)
      details: {
        amount: effectiveAmount,
        priceDiff: simulatedPriceDiff,
        gasCost,
        note: "Simulated - requires actual DEX price comparison",
      },
    };
  }

  return null;
}

/**
 * Detect Sandwich Attack Opportunity
 */
async function detectSandwich(tx) {
  if (!isSwapTransaction(tx)) return null;

  const amount = parseSwapAmount(tx);
  const minAmount = getMinimumAmount(MEV_TYPES.SANDWICH);

  if (DEBUG) {
    console.log(`   🔍 Sandwich check: amount=${amount}, min=${minAmount}`);
  }

  // Accept any swap - lower threshold for testing
  if (amount === 0) {
    // Even if amount is 0, still consider it if it's a swap
    // (might be token-to-token swap where value is 0)
    const effectiveAmount = minAmount;

    // Estimate price impact
    const estimatedPriceImpact = 0.005; // 0.5% price impact
    const frontRunAmount = effectiveAmount * 0.5; // 50% of user's swap
    const estimatedProfit = frontRunAmount * estimatedPriceImpact;
    const gasPrice = await getCurrentGasPrice();
    const gasCost = estimateGasCost(gasPrice, 300000); // ~300k gas for 2 txs
    const netProfit = estimatedProfit - gasCost;

    if (netProfit > MIN_PROFIT_THRESHOLDS[MEV_TYPES.SANDWICH]) {
      return {
        type: MEV_TYPES.SANDWICH,
        profit: netProfit,
        confidence: 0.3, // Lower confidence if amount unknown
        details: {
          userAmount: effectiveAmount,
          frontRunAmount,
          priceImpact: estimatedPriceImpact,
          gasCost,
          note: "Token swap detected - estimated amount",
        },
      };
    }
    return null;
  }

  // Estimate price impact
  const estimatedPriceImpact = 0.005; // 0.5% price impact
  const frontRunAmount = amount * 0.5; // 50% of user's swap
  const estimatedProfit = frontRunAmount * estimatedPriceImpact;
  const gasPrice = await getCurrentGasPrice();
  const gasCost = estimateGasCost(gasPrice, 300000); // ~300k gas for 2 txs
  const netProfit = estimatedProfit - gasCost;

  if (netProfit > MIN_PROFIT_THRESHOLDS[MEV_TYPES.SANDWICH]) {
    return {
      type: MEV_TYPES.SANDWICH,
      profit: netProfit,
      confidence: 0.5, // 50% confidence
      details: {
        userAmount: amount,
        frontRunAmount,
        priceImpact: estimatedPriceImpact,
        gasCost,
      },
    };
  }

  return null;
}

/**
 * Detect Front-Running Opportunity
 */
async function detectFrontRun(tx) {
  // Check if transaction is profitable to front-run
  // This is simplified - in reality, you would analyze:
  // - NFT purchases
  // - Token launches
  // - Governance votes
  // - etc.

  // Only check swaps for front-running (they're most profitable)
  if (!isSwapTransaction(tx)) return null;

  const amount = parseSwapAmount(tx);
  const minAmount = getMinimumAmount(MEV_TYPES.FRONT_RUN);

  if (DEBUG) {
    console.log(`   🔍 Front-run check: amount=${amount}, min=${minAmount}`);
  }

  // Lower threshold - accept any swap
  if (amount === 0) {
    const effectiveAmount = minAmount;
    const estimatedProfit = effectiveAmount * 0.02; // 2% profit
    const gasPrice = await getCurrentGasPrice();
    const gasCost = estimateGasCost(gasPrice, 100000);
    const netProfit = estimatedProfit - gasCost;

    if (netProfit > MIN_PROFIT_THRESHOLDS[MEV_TYPES.FRONT_RUN]) {
      return {
        type: MEV_TYPES.FRONT_RUN,
        profit: netProfit,
        confidence: 0.2, // Lower confidence if amount unknown
        details: {
          amount: effectiveAmount,
          estimatedProfit,
          gasCost,
          note: "Token swap detected - estimated amount",
        },
      };
    }
    return null;
  }

  // Simulated front-run opportunity
  const estimatedProfit = amount * 0.02; // 2% profit
  const gasPrice = await getCurrentGasPrice();
  const gasCost = estimateGasCost(gasPrice, 100000);
  const netProfit = estimatedProfit - gasCost;

  if (netProfit > MIN_PROFIT_THRESHOLDS[MEV_TYPES.FRONT_RUN]) {
    return {
      type: MEV_TYPES.FRONT_RUN,
      profit: netProfit,
      confidence: 0.3, // 30% confidence (high competition)
      details: {
        amount,
        estimatedProfit,
        gasCost,
      },
    };
  }

  return null;
}

/**
 * Detect Liquidation Opportunity
 */
async function detectLiquidation(tx) {
  if (!isLiquidationTransaction(tx)) return null;

  // In reality, you would:
  // 1. Monitor lending protocol positions
  // 2. Calculate health factors
  // 3. Detect when health factor < 1.0

  const amount = parseSwapAmount(tx);
  const minAmount = getMinimumAmount(MEV_TYPES.LIQUIDATION);

  if (DEBUG) {
    console.log(`   🔍 Liquidation check: amount=${amount}, min=${minAmount}`);
  }

  // Lower threshold - accept any liquidation
  const effectiveAmount = amount > 0 ? amount : minAmount;

  // Simulated liquidation opportunity
  const liquidationBonus = 0.05; // 5% bonus
  const estimatedProfit = effectiveAmount * liquidationBonus;
  const gasPrice = await getCurrentGasPrice();
  const gasCost = estimateGasCost(gasPrice, 200000);
  const netProfit = estimatedProfit - gasCost;

  if (netProfit > MIN_PROFIT_THRESHOLDS[MEV_TYPES.LIQUIDATION]) {
    return {
      type: MEV_TYPES.LIQUIDATION,
      profit: netProfit,
      confidence: 0.4, // 40% confidence (high competition)
      details: {
        amount: effectiveAmount,
        liquidationBonus,
        gasCost,
        note: amount === 0 ? "Estimated amount from liquidation" : undefined,
      },
    };
  }

  return null;
}

/**
 * Detect Back-Running Opportunity
 */
async function detectBackRun(tx) {
  // Back-running happens AFTER a transaction is executed
  // This is detected by monitoring executed transactions in blocks
  // For mempool monitoring, we detect large swaps that will create back-run opportunities

  if (!isSwapTransaction(tx)) return null;

  const amount = parseSwapAmount(tx);
  const minAmount = getMinimumAmount(MEV_TYPES.BACK_RUN);

  if (DEBUG) {
    console.log(`   🔍 Back-run check: amount=${amount}, min=${minAmount}`);
  }

  // Lower threshold - accept any swap
  if (amount === 0) {
    const effectiveAmount = minAmount;
    const estimatedPriceImpact = 0.005; // 0.5% price impact
    const recoveryRate = 0.5; // Assume 50% price recovery
    const backRunAmount = effectiveAmount * 0.3; // 30% of user's swap
    const estimatedProfit = backRunAmount * estimatedPriceImpact * recoveryRate;
    const gasPrice = await getCurrentGasPrice();
    const gasCost = estimateGasCost(gasPrice, 150000); // ~150k gas for back-run
    const netProfit = estimatedProfit - gasCost;

    if (netProfit > MIN_PROFIT_THRESHOLDS[MEV_TYPES.BACK_RUN]) {
      return {
        type: MEV_TYPES.BACK_RUN,
        profit: netProfit,
        confidence: 0.4, // Lower confidence if amount unknown
        details: {
          userAmount: effectiveAmount,
          backRunAmount,
          priceImpact: estimatedPriceImpact,
          recoveryRate,
          gasCost,
          note: "Token swap detected - estimated amount",
        },
      };
    }
    return null;
  }

  // Estimate price impact and recovery potential
  const estimatedPriceImpact = 0.005; // 0.5% price impact
  const recoveryRate = 0.5; // Assume 50% price recovery
  const backRunAmount = amount * 0.3; // 30% of user's swap
  const estimatedProfit = backRunAmount * estimatedPriceImpact * recoveryRate;
  const gasPrice = await getCurrentGasPrice();
  const gasCost = estimateGasCost(gasPrice, 150000); // ~150k gas for back-run
  const netProfit = estimatedProfit - gasCost;

  if (netProfit > MIN_PROFIT_THRESHOLDS[MEV_TYPES.BACK_RUN]) {
    return {
      type: MEV_TYPES.BACK_RUN,
      profit: netProfit,
      confidence: 0.6, // 60% confidence (less competition than front-run)
      details: {
        userAmount: amount,
        backRunAmount,
        priceImpact: estimatedPriceImpact,
        recoveryRate,
        gasCost,
      },
    };
  }

  return null;
}

/**
 * Common liquidity function signatures
 */
const LIQUIDITY_FUNCTION_SIGNATURES = {
  addLiquidity: "0xe8e33700",
  addLiquidityETH: "0xf305d719",
  mint: "0x88316456", // Uniswap V3
  increaseLiquidity: "0x219f5d17", // Uniswap V3
  // Add more as needed
};

/**
 * Detect JIT (Just-In-Time) Liquidity Opportunity
 */
async function detectJITLiquidity(tx) {
  // JIT liquidity: Add liquidity before large swap, remove after
  // This requires detecting addLiquidity transactions

  if (!tx || !tx.input) return null;

  // Check if input data starts with a known liquidity function signature
  const inputPrefix = tx.input.toLowerCase().substring(0, 10);

  const isLiquidityTx = Object.values(LIQUIDITY_FUNCTION_SIGNATURES).some(
    (sig) => inputPrefix === sig.toLowerCase()
  );

  if (!isLiquidityTx) return null;

  if (DEBUG) {
    console.log(`   💧 Detected liquidity function: ${inputPrefix}`);
  }

  const amount = parseSwapAmount(tx);
  const minAmount = getMinimumAmount(MEV_TYPES.JIT_LIQUIDITY);

  if (DEBUG) {
    console.log(
      `   🔍 JIT Liquidity check: amount=${amount}, min=${minAmount}`
    );
  }

  // Use minimum amount if parsed amount is too small
  const effectiveAmount = amount > 0 ? amount : minAmount;

  // Estimate fees from swaps in the same block
  // In reality, you would monitor for large swaps after liquidity addition
  const estimatedFees = effectiveAmount * 0.001; // 0.1% fees (simplified)
  const gasPrice = await getCurrentGasPrice();
  const gasCost = estimateGasCost(gasPrice, 400000); // ~400k gas (add + remove)
  const netProfit = estimatedFees - gasCost;

  if (netProfit > MIN_PROFIT_THRESHOLDS[MEV_TYPES.JIT_LIQUIDITY]) {
    return {
      type: MEV_TYPES.JIT_LIQUIDITY,
      profit: netProfit,
      confidence: 0.7, // 70% confidence (requires coordination)
      details: {
        liquidityAmount: effectiveAmount,
        estimatedFees,
        gasCost,
        note: "Requires detecting large swap in same block",
      },
    };
  }

  return null;
}

/**
 * Analyze transaction for MEV opportunities
 */
async function analyzeTransaction(txHash) {
  try {
    transactionCount++;
    const tx = await getTransaction(txHash);
    if (!tx) {
      if (DEBUG) {
        console.log(
          `   ⚠️  Transaction ${txHash} not found (might be mined already)`
        );
      }
      return null;
    }

    // Categorize transaction (increment counters here to avoid double-counting)
    const isSwap = isSwapTransaction(tx, true); // increment count
    const isETH = isETHTransfer(tx);
    const isLiquidation = isLiquidationTransaction(tx);

    if (isETH) {
      ethTransferCount++;
    } else if (!isSwap && !isLiquidation) {
      unknownTxCount++;
    }

    if (DEBUG || SHOW_ALL_TXS) {
      console.log(
        `\n   📝 Transaction #${transactionCount}: ${txHash.substring(
          0,
          16
        )}...`
      );
      console.log(`   📍 To: ${tx.to || "Contract Creation"}`);
      const ethValue = tx.value ? parseInt(tx.value, 16) / 1e18 : 0;
      console.log(`   💰 Value: ${ethValue} ETH`);
      console.log(
        `   📊 Input length: ${tx.input ? tx.input.length : 0} chars`
      );

      if (isETH) {
        console.log(`   ✅ Type: ETH Transfer`);
      } else if (tx.input && tx.input.length >= 10) {
        const funcSig = tx.input.substring(2, 10);
        console.log(`   🔑 Function: 0x${funcSig}`);

        // Check if it matches any known signatures
        const allSignatures = {
          ...SWAP_FUNCTION_SIGNATURES,
          ...LIQUIDATION_FUNCTION_SIGNATURES,
          ...LIQUIDITY_FUNCTION_SIGNATURES,
        };
        const matchingFunc = Object.entries(allSignatures).find(
          ([_, sig]) => sig.toLowerCase() === `0x${funcSig}`.toLowerCase()
        );
        if (matchingFunc) {
          console.log(`   ✅ Recognized as: ${matchingFunc[0]}`);
        } else {
          console.log(`   ❓ Unknown function signature`);
        }
      } else {
        console.log(
          `   ⚠️  No function signature (contract creation or empty input)`
        );
      }
    }

    const opportunities = [];

    // Check for different MEV types
    const arbitrage = await detectArbitrage(tx);
    if (arbitrage) opportunities.push(arbitrage);

    const sandwich = await detectSandwich(tx);
    if (sandwich) opportunities.push(sandwich);

    const frontRun = await detectFrontRun(tx);
    if (frontRun) opportunities.push(frontRun);

    const backRun = await detectBackRun(tx);
    if (backRun) opportunities.push(backRun);

    const liquidation = await detectLiquidation(tx);
    if (liquidation) opportunities.push(liquidation);

    const jitLiquidity = await detectJITLiquidity(tx);
    if (jitLiquidity) opportunities.push(jitLiquidity);

    if ((DEBUG || SHOW_ALL_TXS) && opportunities.length === 0) {
      if (isETH) {
        console.log(`   ℹ️  ETH transfer - no MEV opportunity`);
      } else if (isSwap) {
        console.log(
          `   ⚠️  Swap detected but no profitable MEV opportunity found`
        );
      } else {
        console.log(`   ❌ No MEV opportunities found for this transaction`);
      }
    }

    return opportunities.length > 0 ? opportunities : null;
  } catch (e) {
    if (DEBUG) {
      console.error(`   ❌ Error analyzing transaction ${txHash}:`, e.message);
    }
    return null;
  }
}

/**
 * Display MEV opportunity
 */
function displayOpportunity(txHash, opportunities) {
  opportunityCount++;
  const timestamp = new Date().toLocaleTimeString("en-US", {
    hour12: false,
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    fractionalSecondDigits: 3,
  });

  console.log("\n" + "=".repeat(80));
  console.log(`🔍 MEV OPPORTUNITY #${opportunityCount} [${timestamp}]`);
  console.log(`   Transaction: ${txHash}`);
  console.log("   " + "-".repeat(76));

  for (const opp of opportunities) {
    const profitEth = opp.profit.toFixed(6);
    const profitUsd = (opp.profit * 2000).toFixed(2); // Assuming $2000/ETH
    const confidence = (opp.confidence * 100).toFixed(0);

    console.log(`\n   📊 Type: ${opp.type}`);
    console.log(`   💰 Estimated Profit: ${profitEth} ETH (~$${profitUsd})`);
    console.log(`   📈 Confidence: ${confidence}%`);

    if (opp.details) {
      console.log(`   📋 Details:`);
      for (const [key, value] of Object.entries(opp.details)) {
        if (typeof value === "number") {
          console.log(`      - ${key}: ${value.toFixed(6)}`);
        } else {
          console.log(`      - ${key}: ${value}`);
        }
      }
    }
  }

  console.log("\n   ⚠️  NOTE: This is for educational purposes only!");
  console.log(
    "   ⚠️  Do not automatically execute MEV without proper authorization!"
  );
  console.log("=".repeat(80) + "\n");
}

/**
 * Main monitoring loop
 */
async function startMonitoring() {
  console.log("🔍 MEV Opportunity Detector");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log(`🔌 WebSocket: ${WS_URL}`);
  console.log(`🌐 HTTP RPC: ${HTTP_URL}`);
  console.log(
    `🐛 Debug Mode: ${
      DEBUG ? "ENABLED" : "DISABLED"
    } (set DEBUG=true to enable)`
  );
  console.log(
    `📋 Show All Transactions: ${
      SHOW_ALL_TXS ? "ENABLED" : "DISABLED"
    } (set SHOW_ALL=true to enable)`
  );
  console.log("💡 Monitoring mempool for MEV opportunities...");
  console.log("💡 Press Ctrl+C to stop");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("");

  // Get initial mempool status
  const initialStatus = await getMempoolStatus();
  console.log(
    `📊 Initial Mempool: ${initialStatus.pending} pending, ${initialStatus.queued} queued\n`
  );

  const ws = new WebSocket(WS_URL);

  ws.on("open", () => {
    console.log("✅ Connected to WebSocket\n");

    // Subscribe to new pending transactions
    const subscribeMsg = {
      jsonrpc: "2.0",
      id: 1,
      method: "eth_subscribe",
      params: ["newPendingTransactions"],
    };

    ws.send(JSON.stringify(subscribeMsg));
    console.log("📡 Subscribed to newPendingTransactions\n");
    console.log("💡 Waiting for transactions...\n");
  });

  ws.on("message", async (data) => {
    try {
      const message = JSON.parse(data.toString());

      // Handle subscription confirmation
      if (message.result && typeof message.result === "string") {
        console.log(`✅ Subscribed! Subscription ID: ${message.result}\n`);
        return;
      }

      // Handle transaction notification
      if (message.params && message.params.result) {
        const txHash = message.params.result;

        // Show basic transaction info (always, not just in debug mode)
        if (!DEBUG && !SHOW_ALL_TXS) {
          // Basic logging: show transaction count with stats
          process.stdout.write(
            `\r🔔 Tx #${
              transactionCount + 1
            } | Swaps: ${swapCount} | ETH: ${ethTransferCount} | Other: ${unknownTxCount} | MEV: ${opportunityCount}`
          );
        }

        // Analyze transaction for MEV opportunities
        const opportunities = await analyzeTransaction(txHash);

        if (opportunities && opportunities.length > 0) {
          if (!DEBUG && !SHOW_ALL_TXS) {
            // Clear the line before showing opportunity
            process.stdout.write("\r" + " ".repeat(100) + "\r");
          }
          displayOpportunity(txHash, opportunities);
        } else if (!DEBUG && !SHOW_ALL_TXS) {
          // Continue showing stats on same line
          // (the line is already updated above)
        }
      }
    } catch (e) {
      console.error("⚠️  Error processing message:", e.message);
    }
  });

  ws.on("error", (error) => {
    console.error("❌ WebSocket error:", error.message);
    console.error("💡 Make sure WebSocket is enabled in geth (--ws flag)");
    process.exit(1);
  });

  ws.on("close", () => {
    console.log("\n👋 WebSocket connection closed");
    process.exit(0);
  });

  // Handle Ctrl+C
  process.on("SIGINT", () => {
    // Clear the progress line
    if (!DEBUG && !SHOW_ALL_TXS) {
      process.stdout.write("\r" + " ".repeat(100) + "\r");
    }

    console.log("\n\n📊 Summary:");
    console.log(`   Total transactions analyzed: ${transactionCount}`);
    console.log(`   - Swaps detected: ${swapCount}`);
    console.log(`   - ETH transfers: ${ethTransferCount}`);
    console.log(`   - Other transactions: ${unknownTxCount}`);
    console.log(`   Total MEV opportunities detected: ${opportunityCount}`);
    if (transactionCount > 0) {
      console.log(
        `   MEV detection rate: ${(
          (opportunityCount / transactionCount) *
          100
        ).toFixed(2)}%`
      );
      if (swapCount > 0) {
        console.log(
          `   MEV rate among swaps: ${(
            (opportunityCount / swapCount) *
            100
          ).toFixed(2)}%`
        );
      }
    }
    console.log("\n👋 Stopping...");
    ws.close();
    process.exit(0);
  });
}

// Start monitoring
startMonitoring().catch((error) => {
  console.error("❌ Fatal error:", error);
  process.exit(1);
});
