#!/usr/bin/env node
/**
 * MEV Protection Examples
 * 
 * Các ví dụ code để protect khỏi các loại MEV
 * CHỈ DÙNG CHO MỤC ĐÍCH GIÁO DỤC
 * 
 * Usage: node mev-protection-examples.js
 */

const http = require("http");

const HTTP_URL = process.env.HTTP_URL || "http://localhost:8546";
const FLASHBOTS_RPC = "https://rpc.flashbots.net";

/**
 * RPC Call Helper
 */
function rpcCall(url, method, params = []) {
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

        const req = http.request(url, options, (res) => {
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
 * Example 1: Protected Swap với Slippage Protection
 */
async function protectedSwap(tokenIn, tokenOut, amount, maxSlippage = 0.005) {
    console.log("\n📋 Example 1: Protected Swap với Slippage Protection");
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

    // Get current price
    const currentPrice = await getPrice(tokenIn, tokenOut);
    console.log(`💰 Current Price: ${currentPrice}`);

    // Calculate min amount out
    const minAmountOut = amount * currentPrice * (1 - maxSlippage);
    console.log(`📊 Amount In: ${amount}`);
    console.log(`📊 Min Amount Out: ${minAmountOut} (max slippage: ${maxSlippage * 100}%)`);

    // Build swap transaction
    const swapTx = {
        to: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // Uniswap V2 Router
        data: encodeSwap(tokenIn, tokenOut, amount, minAmountOut),
        gasPrice: await getCurrentGasPrice(),
    };

    console.log("✅ Swap transaction built with slippage protection");
    console.log("⚠️  If price impact > max slippage, transaction will revert");

    return swapTx;
}

/**
 * Example 2: Send Transaction via Flashbots Protect
 */
async function sendViaFlashbotsProtect(transaction) {
    console.log("\n📋 Example 2: Send Transaction via Flashbots Protect");
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

    try {
        // Send via Flashbots Protect RPC
        const result = await rpcCall(
            FLASHBOTS_RPC,
            "eth_sendRawTransaction",
            [transaction]
        );

        console.log("✅ Transaction sent via Flashbots Protect");
        console.log(`📝 TX Hash: ${result}`);
        console.log("💡 Transaction không xuất hiện trong public mempool");
        console.log("💡 Bots không thể detect để front-run/sandwich");

        return result;
    } catch (error) {
        console.error("❌ Error sending via Flashbots:", error.message);
        throw error;
    }
}

/**
 * Example 3: Split Large Swap
 */
async function splitLargeSwap(amount, numSplits = 5) {
    console.log("\n📋 Example 3: Split Large Swap");
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

    const splitAmount = amount / numSplits;
    console.log(`💰 Total Amount: ${amount}`);
    console.log(`📊 Number of Splits: ${numSplits}`);
    console.log(`📊 Amount per Split: ${splitAmount}`);

    const swaps = [];
    for (let i = 0; i < numSplits; i++) {
        swaps.push({
            index: i + 1,
            amount: splitAmount,
            delay: i * 1000, // 1 second between swaps
        });
    }

    console.log("\n📋 Execution Plan:");
    swaps.forEach((swap) => {
        console.log(
            `   ${swap.index}. Swap ${swap.amount} after ${swap.delay}ms delay`
        );
    });

    console.log("\n💡 Benefits:");
    console.log("   - Reduces price impact per swap");
    console.log("   - Makes sandwich attacks less profitable");
    console.log("   - Spreads execution over time");

    return swaps;
}

/**
 * Example 4: Monitor Health Factor
 */
class HealthFactorMonitor {
    constructor(protocol, userAddress) {
        this.protocol = protocol;
        this.userAddress = userAddress;
    }

    async checkHealthFactor() {
        console.log("\n📋 Example 4: Monitor Health Factor");
        console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

        // Simulated health factor calculation
        const position = {
            collateral: 100, // ETH
            debt: 150000, // USDC
            collateralFactor: 0.75,
            collateralPrice: 2000, // USDC per ETH
        };

        const collateralValue = position.collateral * position.collateralPrice;
        const healthFactor =
            (collateralValue * position.collateralFactor) / position.debt;

        console.log(`📊 Collateral: ${position.collateral} ETH`);
        console.log(`📊 Debt: ${position.debt} USDC`);
        console.log(`📊 Health Factor: ${healthFactor.toFixed(4)}`);

        if (healthFactor < 1.0) {
            console.log("❌ DANGER: Health factor < 1.0 - Liquidation risk!");
        } else if (healthFactor < 1.5) {
            console.log("⚠️  WARNING: Health factor < 1.5 - Add collateral");
        } else if (healthFactor < 2.0) {
            console.log("⚠️  CAUTION: Health factor < 2.0 - Monitor closely");
        } else {
            console.log("✅ SAFE: Health factor > 2.0");
        }

        return healthFactor;
    }

    async autoProtect(position) {
        console.log("\n🛡️  Auto-Protect Activated");
        console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

        const repayAmount = position.debt * 0.1; // Repay 10% of debt
        console.log(`💰 Repaying ${repayAmount} USDC to improve health factor`);

        // In production, this would call the protocol's repay function
        console.log("✅ Debt repaid - Health factor improved");
    }
}

/**
 * Example 5: Check Pool Liquidity (Anti-JIT)
 */
async function checkPoolLiquidity(poolAddress, minLiquidity = 1000) {
    console.log("\n📋 Example 5: Check Pool Liquidity (Anti-JIT)");
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

    // Simulated pool liquidity check
    const initialLiquidity = 5000; // ETH
    console.log(`📊 Initial Pool Liquidity: ${initialLiquidity} ETH`);

    // Wait and check again (simulate monitoring)
    console.log("⏳ Monitoring pool for 60 seconds...");

    // Simulate JIT liquidity detection
    const currentLiquidity = 5500; // Increased by 10%
    const liquidityChange = ((currentLiquidity - initialLiquidity) / initialLiquidity) * 100;

    console.log(`📊 Current Pool Liquidity: ${currentLiquidity} ETH`);
    console.log(`📊 Liquidity Change: ${liquidityChange.toFixed(2)}%`);

    if (liquidityChange > 10) {
        console.log("⚠️  WARNING: Significant liquidity increase detected");
        console.log("⚠️  Possible JIT liquidity - Consider using different pool");
    } else if (currentLiquidity < minLiquidity) {
        console.log("⚠️  WARNING: Pool liquidity too low");
        console.log("⚠️  Risk of JIT liquidity manipulation");
    } else {
        console.log("✅ Pool liquidity looks safe");
    }

    return {
        initial: initialLiquidity,
        current: currentLiquidity,
        change: liquidityChange,
        safe: liquidityChange < 10 && currentLiquidity >= minLiquidity,
    };
}

/**
 * Example 6: Batch Transactions
 */
async function batchTransactions(transactions) {
    console.log("\n📋 Example 6: Batch Transactions");
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

    console.log(`📊 Number of Transactions: ${transactions.length}`);

    // Encode batch transaction
    const batchTx = {
        to: "0x...", // Batch router address
        data: encodeBatch(transactions),
        gasPrice: await getCurrentGasPrice(),
    };

    console.log("✅ Batch transaction created");
    console.log("💡 All transactions will execute in same block");
    console.log("💡 Reduces time window for back-running");

    return batchTx;
}

/**
 * Helper Functions
 */
async function getPrice(tokenIn, tokenOut) {
    // Simulated price fetch
    return 2000; // 1 ETH = 2000 USDC
}

async function getCurrentGasPrice() {
    try {
        const gasPriceHex = await rpcCall(HTTP_URL, "eth_gasPrice", []);
        return parseInt(gasPriceHex, 16);
    } catch (e) {
        return 20000000000; // 20 gwei default
    }
}

function encodeSwap(tokenIn, tokenOut, amount, minAmountOut) {
    // Simplified - in production, use proper ABI encoding
    return "0x" + "swap".padEnd(64, "0");
}

function encodeBatch(transactions) {
    // Simplified - in production, use proper ABI encoding
    return "0x" + "batch".padEnd(64, "0");
}

/**
 * Main Examples
 */
async function runExamples() {
    console.log("🛡️  MEV Protection Examples");
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    console.log("");

    try {
        // Example 1: Protected Swap
        await protectedSwap("ETH", "USDC", 10, 0.005);

        // Example 2: Flashbots Protect (commented out - requires real setup)
        // await sendViaFlashbotsProtect("0x...");

        // Example 3: Split Large Swap
        await splitLargeSwap(100, 5);

        // Example 4: Health Factor Monitor
        const monitor = new HealthFactorMonitor("aave", "0x...");
        await monitor.checkHealthFactor();

        // Example 5: Check Pool Liquidity
        await checkPoolLiquidity("0x...", 1000);

        // Example 6: Batch Transactions
        await batchTransactions([
            { to: "0x...", data: "0x..." },
            { to: "0x...", data: "0x..." },
        ]);

        console.log("\n✅ All examples completed!");
        console.log("💡 See scripts/MEV-PROTECTION.md for detailed documentation");
    } catch (error) {
        console.error("\n❌ Error running examples:", error.message);
    }
}

// Run examples if executed directly
if (require.main === module) {
    runExamples();
}

module.exports = {
    protectedSwap,
    sendViaFlashbotsProtect,
    splitLargeSwap,
    HealthFactorMonitor,
    checkPoolLiquidity,
    batchTransactions,
};

