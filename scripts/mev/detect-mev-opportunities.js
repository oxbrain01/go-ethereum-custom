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
const MIN_PROFIT_THRESHOLDS = {
  [MEV_TYPES.ARBITRAGE]: 0.001, // 0.001 ETH
  [MEV_TYPES.LIQUIDATION]: 0.01, // 0.01 ETH
  [MEV_TYPES.SANDWICH]: 0.0005, // 0.0005 ETH
  [MEV_TYPES.FRONT_RUN]: 0.005, // 0.005 ETH
  [MEV_TYPES.BACK_RUN]: 0.001, // 0.001 ETH
  [MEV_TYPES.JIT_LIQUIDITY]: 0.01, // 0.01 ETH
};

let opportunityCount = 0;

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
 * Check if transaction is a swap
 */
function isSwapTransaction(tx) {
  if (!tx || !tx.to) return false;

  // Common DEX contract addresses (example - adjust for your network)
  const dexAddresses = [
    "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // Uniswap V2 Router
    "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F", // Sushiswap Router
    // Add more DEX addresses
  ];

  return dexAddresses.some((addr) =>
    tx.to.toLowerCase().includes(addr.toLowerCase())
  );
}

/**
 * Check if transaction is a liquidation
 */
function isLiquidationTransaction(tx) {
  if (!tx || !tx.to) return false;

  // Common lending protocol addresses
  const lendingProtocols = [
    "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9", // Aave Lending Pool
    "0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B", // Compound Comptroller
    // Add more protocol addresses
  ];

  return lendingProtocols.some((addr) =>
    tx.to.toLowerCase().includes(addr.toLowerCase())
  );
}

/**
 * Parse swap amount from transaction
 */
function parseSwapAmount(tx) {
  if (!tx || !tx.value) return 0;
  return parseInt(tx.value, 16) / 1e18; // Convert from Wei to ETH
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
  if (amount < 1) return null; // Too small

  // Simulated arbitrage detection
  // In production, you would query actual DEX prices
  const simulatedPriceDiff = 0.001; // 0.1% price difference
  const estimatedProfit = amount * simulatedPriceDiff;
  const gasPrice = await getCurrentGasPrice();
  const gasCost = estimateGasCost(gasPrice, 150000); // ~150k gas for arbitrage
  const netProfit = estimatedProfit - gasCost;

  if (netProfit > MIN_PROFIT_THRESHOLDS[MEV_TYPES.ARBITRAGE]) {
    return {
      type: MEV_TYPES.ARBITRAGE,
      profit: netProfit,
      confidence: 0.6, // 60% confidence (simulated)
      details: {
        amount,
        priceDiff: simulatedPriceDiff,
        gasCost,
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
  if (amount < 5) return null; // Need large swap for sandwich

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

  const amount = parseSwapAmount(tx);
  if (amount < 10) return null; // Need significant amount

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
  if (amount < 1) return null;

  // Simulated liquidation opportunity
  const liquidationBonus = 0.05; // 5% bonus
  const estimatedProfit = amount * liquidationBonus;
  const gasPrice = await getCurrentGasPrice();
  const gasCost = estimateGasCost(gasPrice, 200000);
  const netProfit = estimatedProfit - gasCost;

  if (netProfit > MIN_PROFIT_THRESHOLDS[MEV_TYPES.LIQUIDATION]) {
    return {
      type: MEV_TYPES.LIQUIDATION,
      profit: netProfit,
      confidence: 0.4, // 40% confidence (high competition)
      details: {
        amount,
        liquidationBonus,
        gasCost,
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
  if (amount < 10) return null; // Need significant amount to create price impact

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
 * Detect JIT (Just-In-Time) Liquidity Opportunity
 */
async function detectJITLiquidity(tx) {
  // JIT liquidity: Add liquidity before large swap, remove after
  // This requires detecting addLiquidity transactions

  if (!tx || !tx.to) return null;

  // Common liquidity pool addresses (Uniswap V3, etc.)
  const liquidityPoolAddresses = [
    "0xC36442b4a4522E871399CD717aBDD847Ab11FE88", // Uniswap V3 Position Manager
    // Add more liquidity pool addresses
  ];

  const isLiquidityTx = liquidityPoolAddresses.some((addr) =>
    tx.to.toLowerCase().includes(addr.toLowerCase())
  );

  if (!isLiquidityTx) return null;

  const amount = parseSwapAmount(tx);
  if (amount < 50) return null; // Need significant liquidity addition

  // Estimate fees from swaps in the same block
  // In reality, you would monitor for large swaps after liquidity addition
  const estimatedFees = amount * 0.001; // 0.1% fees (simplified)
  const gasPrice = await getCurrentGasPrice();
  const gasCost = estimateGasCost(gasPrice, 400000); // ~400k gas (add + remove)
  const netProfit = estimatedFees - gasCost;

  if (netProfit > MIN_PROFIT_THRESHOLDS[MEV_TYPES.JIT_LIQUIDITY]) {
    return {
      type: MEV_TYPES.JIT_LIQUIDITY,
      profit: netProfit,
      confidence: 0.7, // 70% confidence (requires coordination)
      details: {
        liquidityAmount: amount,
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
    const tx = await getTransaction(txHash);
    if (!tx) return null;

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

    return opportunities.length > 0 ? opportunities : null;
  } catch (e) {
    console.error(`Error analyzing transaction ${txHash}:`, e.message);
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

        // Analyze transaction for MEV opportunities
        const opportunities = await analyzeTransaction(txHash);

        if (opportunities && opportunities.length > 0) {
          displayOpportunity(txHash, opportunities);
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
    console.log("\n\n📊 Summary:");
    console.log(`   Total opportunities detected: ${opportunityCount}`);
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
