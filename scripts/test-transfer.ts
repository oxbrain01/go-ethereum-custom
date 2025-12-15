#!/usr/bin/env ts-node
/**
 * Script to test blockchain transactions by transferring ETH between test accounts
 *
 * Usage:
 *   ts-node scripts/test-transfer.ts [from_account_index] [to_account_index] [amount_in_eth]
 *
 * Examples:
 *   ts-node scripts/test-transfer.ts                    # Transfer 0.1 ETH from account 0 to account 1
 *   ts-node scripts/test-transfer.ts 0 2 0.5           # Transfer 0.5 ETH from account 0 to account 2
 *   ts-node scripts/test-transfer.ts 1 0 1.0           # Transfer 1.0 ETH from account 1 to account 0
 *
 * Requirements:
 *   - Node must be running (./scripts/start-node1.sh)
 *   - Sender account must have sufficient balance
 */

import { ethers } from "ethers";
import * as fs from "fs";
import * as path from "path";
import { execSync } from "child_process";

// Configuration
const HTTP_PORT = 8546;
const RPC_URL = `http://localhost:${HTTP_PORT}`;
// Get script directory - works with both ts-node and compiled JS
function getScriptDir(): string {
  // Try different methods to get the script directory
  if (require.main?.filename) {
    return path.dirname(require.main.filename);
  }
  // For ts-node, process.argv[1] contains the script path
  if (process.argv[1]) {
    return path.dirname(path.resolve(process.argv[1]));
  }
  // Fallback to current working directory
  return process.cwd();
}
const SCRIPT_DIR = getScriptDir();
const TEST_ACCOUNTS_FILE = path.join(SCRIPT_DIR, "test-accounts.json");

// Colors for console output
const colors = {
  reset: "\x1b[0m",
  red: "\x1b[31m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
};

interface TestAccount {
  address: string;
  privateKey: string;
  password: string;
  balance: string;
}

interface TestAccounts {
  accounts: TestAccount[];
}

async function main() {
  console.log(
    `${colors.blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${colors.reset}`
  );
  console.log(`${colors.blue}🧪 Blockchain Transaction Test${colors.reset}`);
  console.log(
    `${colors.blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${colors.reset}`
  );
  console.log("");

  // Parse command line arguments
  const args = process.argv.slice(2);
  const fromIndex = args[0] ? parseInt(args[0], 10) : 0;
  const toIndex = args[1] ? parseInt(args[1], 10) : 1;
  const amountEth = args[2] ? parseFloat(args[2]) : 0.1;

  // Load test accounts
  console.log(`${colors.yellow}📋 Loading test accounts...${colors.reset}`);

  if (!fs.existsSync(TEST_ACCOUNTS_FILE)) {
    console.error(
      `${colors.red}❌ Test accounts file not found: ${TEST_ACCOUNTS_FILE}${colors.reset}`
    );
    process.exit(1);
  }

  const accountsData: TestAccounts = JSON.parse(
    fs.readFileSync(TEST_ACCOUNTS_FILE, "utf-8")
  );

  const accountCount = accountsData.accounts.length;
  console.log(
    `${colors.green}✅ Found ${accountCount} test accounts${colors.reset}`
  );

  // Validate indices
  if (fromIndex < 0 || fromIndex >= accountCount) {
    console.error(
      `${colors.red}❌ Invalid from account index: ${fromIndex} (valid: 0-${
        accountCount - 1
      })${colors.reset}`
    );
    process.exit(1);
  }

  if (toIndex < 0 || toIndex >= accountCount) {
    console.error(
      `${colors.red}❌ Invalid to account index: ${toIndex} (valid: 0-${
        accountCount - 1
      })${colors.reset}`
    );
    process.exit(1);
  }

  if (fromIndex === toIndex) {
    console.error(
      `${colors.red}❌ From and to accounts cannot be the same${colors.reset}`
    );
    process.exit(1);
  }

  const fromAccount = accountsData.accounts[fromIndex];
  const toAccount = accountsData.accounts[toIndex];

  if (!fromAccount || !toAccount) {
    console.error(`${colors.red}❌ Failed to load accounts${colors.reset}`);
    process.exit(1);
  }

  console.log(`${colors.green}✅ Accounts loaded${colors.reset}`);
  console.log(
    `   From: ${colors.blue}${fromAccount.address}${colors.reset} (index ${fromIndex})`
  );
  console.log(
    `   To:   ${colors.blue}${toAccount.address}${colors.reset} (index ${toIndex})`
  );
  console.log(`   Amount: ${colors.blue}${amountEth} ETH${colors.reset}`);
  console.log("");

  // Connect to provider
  console.log(`${colors.yellow}🔍 Testing RPC connection...${colors.reset}`);

  let provider: ethers.JsonRpcProvider;
  try {
    provider = new ethers.JsonRpcProvider(RPC_URL);
    const blockNumber = await provider.getBlockNumber(); // Test connection
    console.log(`${colors.green}✅ RPC connection successful${colors.reset}`);
    console.log(`   Current block: ${blockNumber}`);

    // Warn if blockchain is not producing blocks, and try to unlock validators
    if (blockNumber === 0) {
      console.log("");
      console.log(
        `${colors.yellow}⚠️  WARNING: Blockchain is at block 0${colors.reset}`
      );
      console.log(
        `${colors.yellow}   Blocks are not being produced. Attempting to unlock validators...${colors.reset}`
      );
      console.log("");

      // Try to unlock validators automatically
      const projectRoot = path.resolve(SCRIPT_DIR, "..");
      const node1Datadir = path.join(
        process.env.HOME || "",
        "local-testnet-node1"
      );
      const node2Datadir = path.join(
        process.env.HOME || "",
        "local-testnet-node2"
      );
      const gethPath = path.join(projectRoot, "build", "bin", "geth");

      let unlocked = false;

      // Try to read validator addresses
      try {
        const node1ValidatorFile = path.join(
          node1Datadir,
          "validator_address.txt"
        );
        const node2ValidatorFile = path.join(
          node2Datadir,
          "validator_address.txt"
        );
        const passwordFile = path.join(node1Datadir, "password.txt");

        if (fs.existsSync(node1ValidatorFile) && fs.existsSync(gethPath)) {
          const node1Validator = fs
            .readFileSync(node1ValidatorFile, "utf-8")
            .trim();
          const node2Validator = fs.existsSync(node2ValidatorFile)
            ? fs.readFileSync(node2ValidatorFile, "utf-8").trim()
            : null;
          const password = fs.existsSync(passwordFile)
            ? fs.readFileSync(passwordFile, "utf-8").trim()
            : "validator123";

          console.log(
            `${colors.yellow}   Attempting to unlock validators...${colors.reset}`
          );

          // Note: Personal API is deprecated and not available via RPC
          // Validators must be unlocked manually in interactive console sessions
          console.log(
            `${colors.yellow}   ⚠️  Personal API is not available via RPC${colors.reset}`
          );
          console.log(
            `${colors.yellow}   Validators must be unlocked manually in geth console${colors.reset}`
          );
          console.log("");
          console.log(
            `${colors.blue}   To unlock validators, run these commands in separate terminals:${colors.reset}`
          );
          console.log(
            `   ${colors.blue}Terminal 1:${colors.reset} ./build/bin/geth attach --datadir ~/local-testnet-node1`
          );
          console.log(
            `   ${colors.blue}         Then:${colors.reset} personal.unlockAccount('${node1Validator}', '${password}', 0)`
          );
          if (node2Validator) {
            console.log(
              `   ${colors.blue}Terminal 2:${colors.reset} ./build/bin/geth attach --datadir ~/local-testnet-node2`
            );
            console.log(
              `   ${colors.blue}         Then:${colors.reset} personal.unlockAccount('${node2Validator}', '${password}', 0)`
            );
          }
          console.log("");

          // Try to run the unlock-validators script first (newer, better script)
          const unlockScript = path.join(
            projectRoot,
            "scripts",
            "unlock-validators.sh"
          );
          const autoUnlockScript = path.join(
            projectRoot,
            "scripts",
            "auto-unlock-and-mine.sh"
          );

          // Try the new unlock-validators.sh first
          if (fs.existsSync(unlockScript)) {
            try {
              console.log(
                `${colors.yellow}   Running unlock-validators script...${colors.reset}`
              );
              execSync(`bash "${unlockScript}"`, {
                encoding: "utf-8",
                timeout: 30000,
                cwd: projectRoot,
                stdio: "pipe",
              });
              // Wait a bit for blocks to start
              console.log(
                `${colors.yellow}   Waiting for blocks to start...${colors.reset}`
              );
              for (let i = 0; i < 20; i++) {
                await new Promise((resolve) => setTimeout(resolve, 1000));
                const checkBlock = await provider.getBlockNumber();
                if (checkBlock > 0) {
                  console.log(
                    `${colors.green}   ✅ Blocks are now being produced! (block ${checkBlock})${colors.reset}`
                  );
                  unlocked = true;
                  break;
                }
                if (i % 5 === 0 && i > 0) {
                  process.stdout.write(".");
                }
              }
              console.log("");
            } catch (e: any) {
              console.log(
                `${colors.yellow}   ⚠️  Unlock script may have issues: ${e.message}${colors.reset}`
              );
            }
          } else if (fs.existsSync(autoUnlockScript)) {
            // Fallback to old auto-unlock script
            try {
              console.log(
                `${colors.yellow}   Running auto-unlock script (fallback)...${colors.reset}`
              );
              execSync(`bash "${autoUnlockScript}"`, {
                encoding: "utf-8",
                timeout: 30000,
                cwd: projectRoot,
                stdio: "pipe",
              });
              // Wait a bit for blocks to start
              console.log(
                `${colors.yellow}   Waiting for blocks to start...${colors.reset}`
              );
              for (let i = 0; i < 20; i++) {
                await new Promise((resolve) => setTimeout(resolve, 1000));
                const checkBlock = await provider.getBlockNumber();
                if (checkBlock > 0) {
                  console.log(
                    `${colors.green}   ✅ Blocks are now being produced! (block ${checkBlock})${colors.reset}`
                  );
                  unlocked = true;
                  break;
                }
                if (i % 5 === 0 && i > 0) {
                  process.stdout.write(".");
                }
              }
              console.log("");
            } catch (e: any) {
              console.log(
                `${colors.yellow}   ⚠️  Auto-unlock script may have issues: ${e.message}${colors.reset}`
              );
            }
          } else {
            // Try RPC unlock method
            try {
              console.log(
                `${colors.yellow}   Attempting unlock via RPC...${colors.reset}`
              );

              // Try to unlock via RPC (Node 1 - port 8546)
              try {
                const unlockRpc1 = `curl -s -X POST "http://localhost:8546" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"personal_unlockAccount","params":["${node1Validator}", "${password}", 0],"id":1}'`;
                const result1 = execSync(unlockRpc1, {
                  encoding: "utf-8",
                  timeout: 10000,
                  stdio: "pipe",
                });
                if (result1.includes('"result":true')) {
                  console.log(
                    `${colors.green}   ✅ Node 1 validator unlocked via RPC${colors.reset}`
                  );
                }
              } catch (e: any) {
                // RPC unlock may not be available
              }

              // Try to unlock Node 2 via RPC (port 8548)
              if (node2Validator) {
                try {
                  const unlockRpc2 = `curl -s -X POST "http://localhost:8548" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"personal_unlockAccount","params":["${node2Validator}", "${password}", 0],"id":1}'`;
                  const result2 = execSync(unlockRpc2, {
                    encoding: "utf-8",
                    timeout: 10000,
                    stdio: "pipe",
                  });
                  if (result2.includes('"result":true')) {
                    console.log(
                      `${colors.green}   ✅ Node 2 validator unlocked via RPC${colors.reset}`
                    );
                  }
                } catch (e: any) {
                  // RPC unlock may not be available
                }
              }

              // Wait and check if blocks started
              console.log(
                `${colors.yellow}   Waiting for blocks to start...${colors.reset}`
              );
              for (let i = 0; i < 15; i++) {
                await new Promise((resolve) => setTimeout(resolve, 1000));
                const checkBlock = await provider.getBlockNumber();
                if (checkBlock > 0) {
                  console.log(
                    `${colors.green}   ✅ Blocks are now being produced! (block ${checkBlock})${colors.reset}`
                  );
                  unlocked = true;
                  break;
                }
                if (i % 5 === 0 && i > 0) {
                  process.stdout.write(".");
                }
              }
              console.log("");
            } catch (e: any) {
              // Unlock failed
            }
          }

          if (unlocked) {
            console.log("");
            console.log(
              `${colors.yellow}   Waiting 15 seconds for blocks to start being produced...${colors.reset}`
            );
            for (let i = 0; i < 15; i++) {
              await new Promise((resolve) => setTimeout(resolve, 1000));
              const currentBlock = await provider.getBlockNumber();
              if (currentBlock > 0) {
                console.log(
                  `${colors.green}   ✅ Blocks are now being produced! (block ${currentBlock})${colors.reset}`
                );
                console.log("");
                break;
              }
              process.stdout.write(".");
            }
            console.log("");
          }
        }
      } catch (error) {
        // If unlock fails, continue anyway
        console.log(
          `${colors.yellow}   Could not auto-unlock validators. Continuing...${colors.reset}`
        );
        console.log("");
      }

      const finalBlockCheck = await provider.getBlockNumber();
      if (finalBlockCheck === 0) {
        console.log(
          `${colors.yellow}   Still at block 0. Transaction will be sent but may not be mined.${colors.reset}`
        );
        console.log(
          `${colors.yellow}   To fix manually: ./scripts/unlock-validator.sh node1${colors.reset}`
        );
        console.log("");
      }
    }
  } catch (error) {
    console.error(
      `${colors.red}❌ Cannot connect to RPC endpoint at ${RPC_URL}${colors.reset}`
    );
    console.error("   Make sure the node is running: ./scripts/start-node1.sh");
    process.exit(1);
  }

  // Check balances
  console.log(`${colors.yellow}💰 Checking balances...${colors.reset}`);

  const fromBalance = await provider.getBalance(fromAccount.address);
  const toBalance = await provider.getBalance(toAccount.address);

  const fromBalanceEth = parseFloat(ethers.formatEther(fromBalance));
  const toBalanceEth = parseFloat(ethers.formatEther(toBalance));

  console.log(
    `   From balance: ${colors.green}${fromBalanceEth.toFixed(6)} ETH${
      colors.reset
    }`
  );
  console.log(
    `   To balance:   ${colors.green}${toBalanceEth.toFixed(6)} ETH${
      colors.reset
    }`
  );
  console.log("");

  // Convert amount to wei
  const amountWei = ethers.parseEther(amountEth.toString());

  // Get gas price and estimate gas
  const gasPrice = await provider.getFeeData();
  const gasLimit = 21000n; // Standard transfer gas limit

  if (!gasPrice.gasPrice) {
    console.error(`${colors.red}❌ Failed to get gas price${colors.reset}`);
    process.exit(1);
  }

  const gasCost = gasPrice.gasPrice * gasLimit;
  const totalNeeded = amountWei + gasCost;

  // Check if sender has enough balance
  if (fromBalance < totalNeeded) {
    console.error(`${colors.red}❌ Insufficient balance!${colors.reset}`);
    console.error(
      `   Required: ${colors.red}${ethers.formatEther(totalNeeded)} ETH${
        colors.reset
      }`
    );
    console.error(
      `   Available: ${colors.green}${fromBalanceEth.toFixed(6)} ETH${
        colors.reset
      }`
    );
    process.exit(1);
  }

  // Get nonce (use 'pending' to include pending transactions)
  console.log(`${colors.yellow}📝 Getting transaction nonce...${colors.reset}`);
  const nonce = await provider.getTransactionCount(
    fromAccount.address,
    "pending"
  );
  console.log(`${colors.green}✅ Nonce: ${nonce}${colors.reset}`);
  console.log("");

  // Get chain ID
  const network = await provider.getNetwork();
  const chainId = Number(network.chainId);

  // Create wallet from private key
  console.log(
    `${colors.yellow}🔐 Creating and signing transaction...${colors.reset}`
  );

  const wallet = new ethers.Wallet(fromAccount.privateKey, provider);

  // Create transaction
  const tx = {
    to: toAccount.address,
    value: amountWei,
    gasLimit: gasLimit,
    gasPrice: gasPrice.gasPrice,
    nonce: nonce,
    chainId: chainId,
  };

  console.log("Transaction details:");
  console.log(`  From: ${fromAccount.address}`);
  console.log(`  To: ${toAccount.address}`);
  console.log(`  Value: ${amountEth} ETH`);
  console.log(
    `  Gas Price: ${ethers.formatUnits(gasPrice.gasPrice, "gwei")} gwei`
  );
  console.log(`  Gas Limit: ${gasLimit}`);
  console.log(`  Nonce: ${nonce}`);
  console.log(`  Chain ID: ${chainId}`);
  console.log("");

  try {
    // Sign and send transaction
    console.log(`${colors.yellow}📤 Sending transaction...${colors.reset}`);
    const txResponse = await wallet.sendTransaction(tx);

    console.log(
      `${colors.green}✅ Transaction sent successfully!${colors.reset}`
    );
    console.log(
      `   Transaction Hash: ${colors.blue}${txResponse.hash}${colors.reset}`
    );
    console.log("");

    // Wait for transaction to be mined using polling with block monitoring
    console.log(
      `${colors.yellow}⏳ Waiting for transaction to be mined...${colors.reset}`
    );

    let receipt: ethers.TransactionReceipt | null = null;
    const maxWait = 60; // Increased wait time
    let waitCount = 0;
    let lastBlockNumber = await provider.getBlockNumber();
    let blocksProduced = 0;

    while (waitCount < maxWait) {
      try {
        receipt = await provider.getTransactionReceipt(txResponse.hash);
        if (receipt) {
          break;
        }
      } catch (error: any) {
        // Ignore indexing errors - they're temporary
        if (
          !error.message ||
          !error.message.includes("indexing is in progress")
        ) {
          // For other errors, continue trying
        }
      }

      // Check if blocks are being produced
      const currentBlock = await provider.getBlockNumber();
      if (currentBlock > lastBlockNumber) {
        blocksProduced++;
        lastBlockNumber = currentBlock;
        if (blocksProduced === 1) {
          console.log("");
          console.log(
            `${colors.green}   ✅ Blocks are now being produced! (block ${currentBlock})${colors.reset}`
          );
          console.log(
            `${colors.yellow}   Continuing to wait for transaction...${colors.reset}`
          );
        }
      }

      process.stdout.write(".");
      await new Promise((resolve) => setTimeout(resolve, 1000));
      waitCount++;
    }

    console.log("");

    if (!receipt) {
      const currentBlock = await provider.getBlockNumber();
      console.log(
        `${colors.yellow}⚠️  Transaction not mined yet (waited ${maxWait}s)${colors.reset}`
      );
      console.log(
        `${colors.yellow}   Transaction hash: ${txResponse.hash}${colors.reset}`
      );

      if (currentBlock === 0) {
        // Try one more time to unlock validators
        console.log("");
        console.log(
          `${colors.yellow}   Attempting to unlock validators one more time...${colors.reset}`
        );
        const projectRoot = path.resolve(SCRIPT_DIR, "..");
        const unlockScript = path.join(
          projectRoot,
          "scripts",
          "unlock-validators.sh"
        );
        const autoUnlockScript = path.join(
          projectRoot,
          "scripts",
          "auto-unlock-and-mine.sh"
        );

        // Try ensure-mining.sh first (comprehensive script)
        const ensureMiningScript = path.join(
          projectRoot,
          "scripts",
          "ensure-mining.sh"
        );

        // Try unlock-validators.sh first
        if (fs.existsSync(unlockScript)) {
          try {
            console.log(
              `${colors.yellow}   Running unlock-validators script...${colors.reset}`
            );
            execSync(`bash "${unlockScript}"`, {
              encoding: "utf-8",
              timeout: 45000,
              cwd: projectRoot,
              stdio: "pipe",
            });
            // Wait a bit more
            console.log(
              `${colors.yellow}   Waiting 15 more seconds for blocks...${colors.reset}`
            );
            for (let i = 0; i < 15; i++) {
              await new Promise((resolve) => setTimeout(resolve, 1000));
              const checkBlock = await provider.getBlockNumber();
              if (checkBlock > 0) {
                console.log(
                  `${colors.green}   ✅ Blocks started! Checking transaction again...${colors.reset}`
                );
                // Try to get receipt one more time
                try {
                  receipt = await provider.getTransactionReceipt(
                    txResponse.hash
                  );
                  if (receipt) {
                    console.log(
                      `${colors.green}   ✅ Transaction found!${colors.reset}`
                    );
                    console.log("");
                    // Continue to balance check below
                  }
                } catch (e) {
                  // Continue
                }
              }
            }
          } catch (e: any) {
            // Unlock failed, try fallback
            if (fs.existsSync(autoUnlockScript)) {
              try {
                execSync(`bash "${autoUnlockScript}"`, {
                  encoding: "utf-8",
                  timeout: 30000,
                  cwd: projectRoot,
                  stdio: "pipe",
                });
              } catch (e2: any) {
                // Both failed
              }
            }
          }
        } else if (fs.existsSync(autoUnlockScript)) {
          // Fallback to old script
          try {
            execSync(`bash "${autoUnlockScript}"`, {
              encoding: "utf-8",
              timeout: 30000,
              cwd: projectRoot,
              stdio: "pipe",
            });
          } catch (e: any) {
            // Unlock failed
          }
        }

        // Only show error if we still don't have a receipt
        if (!receipt) {
          console.log("");
          console.log(
            `${colors.red}❌ Blockchain is still at block 0 - no blocks are being produced!${colors.reset}`
          );
          console.log(
            `${colors.yellow}   This means validators are not creating blocks.${colors.reset}`
          );
          console.log("");
          console.log(
            `${colors.yellow}   Quick fix - run in separate terminals:${colors.reset}`
          );
          console.log(`   ${colors.blue}Terminal 1:${colors.reset}`);
          console.log(
            `      ${colors.blue}./build/bin/geth attach --datadir ~/local-testnet-node1${colors.reset}`
          );
          console.log(
            `      ${colors.blue}> personal.unlockAccount('0xB49433628173fc5b51bf3Af6B7F96c8EFc1626EC', 'validator123', 0)${colors.reset}`
          );
          console.log(`   ${colors.blue}Terminal 2:${colors.reset}`);
          console.log(
            `      ${colors.blue}./build/bin/geth attach --datadir ~/local-testnet-node2${colors.reset}`
          );
          console.log(
            `      ${colors.blue}> personal.unlockAccount('0x36D84C24395ABC90006C3FF19292a54eDf591ac3', 'validator123', 0)${colors.reset}`
          );
          console.log("");
          console.log(
            `${colors.yellow}   Or run: ./scripts/auto-unlock-and-mine.sh${colors.reset}`
          );
          console.log("");
          console.log(
            `${colors.yellow}   Transaction is in the mempool and will be mined once blocks start being produced.${colors.reset}`
          );
        }
      } else if (blocksProduced > 0) {
        console.log(
          `${colors.yellow}   Blocks are being produced (current: ${currentBlock}), but transaction not confirmed yet.${colors.reset}`
        );
        console.log(
          `${colors.yellow}   Transaction may be in a future block. Check status later with:${colors.reset}`
        );
      } else {
        console.log(
          `${colors.yellow}   Current block: ${currentBlock}${colors.reset}`
        );
        console.log(
          `${colors.yellow}   Transaction may still be pending. Check status later with:${colors.reset}`
        );
      }
      console.log(
        `${colors.blue}   curl -X POST ${RPC_URL} -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_getTransactionReceipt\",\"params\":[\"${txResponse.hash}\"],\"id\":1}'${colors.reset}`
      );
      process.exit(0);
    }

    if (receipt && receipt.status === 1) {
      console.log(`${colors.green}✅ Transaction confirmed!${colors.reset}`);
      console.log(
        `   Block Number: ${colors.blue}${receipt.blockNumber}${colors.reset}`
      );
      console.log(`   Gas Used: ${receipt.gasUsed.toString()}`);
      console.log("");

      // Check new balances
      console.log(`${colors.yellow}💰 Checking new balances...${colors.reset}`);

      // Wait a moment for state to update
      await new Promise((resolve) => setTimeout(resolve, 1000));

      const fromBalanceNew = await provider.getBalance(fromAccount.address);
      const toBalanceNew = await provider.getBalance(toAccount.address);

      const fromBalanceNewEth = parseFloat(ethers.formatEther(fromBalanceNew));
      const toBalanceNewEth = parseFloat(ethers.formatEther(toBalanceNew));

      const fromDiff = fromBalanceNewEth - fromBalanceEth;
      const toDiff = toBalanceNewEth - toBalanceEth;

      // Calculate expected values for verification
      const actualGasUsed = receipt.gasUsed;
      // Get gas price from receipt or use the transaction gas price
      let actualGasPrice = receipt.gasPrice;
      if (!actualGasPrice) {
        // Try to get from the transaction
        const txData = await provider.getTransaction(receipt.hash);
        actualGasPrice = txData?.gasPrice || gasPrice.gasPrice!;
      }
      const actualGasCost = actualGasPrice * actualGasUsed;
      const actualGasCostEth = parseFloat(ethers.formatEther(actualGasCost));
      const expectedFromDiff = -(amountEth + actualGasCostEth);
      const expectedToDiff = amountEth;

      // Verify balance changes
      const fromDiffTolerance = 0.000001; // Allow small floating point differences
      const toDiffTolerance = 0.000001;
      const fromDiffMatches =
        Math.abs(fromDiff - expectedFromDiff) < fromDiffTolerance;
      const toDiffMatches = Math.abs(toDiff - expectedToDiff) < toDiffTolerance;

      console.log(
        `   From balance: ${colors.green}${fromBalanceNewEth.toFixed(6)} ETH${
          colors.reset
        } (was ${fromBalanceEth.toFixed(6)} ETH)`
      );
      console.log(
        `   To balance:   ${colors.green}${toBalanceNewEth.toFixed(6)} ETH${
          colors.reset
        } (was ${toBalanceEth.toFixed(6)} ETH)`
      );
      console.log("");
      console.log(`${colors.yellow}📊 Balance Changes:${colors.reset}`);
      console.log(
        `   From change: ${colors.red}${fromDiff.toFixed(6)} ETH${colors.reset}`
      );
      console.log(
        `     - Amount sent: ${colors.red}${amountEth.toFixed(6)} ETH${
          colors.reset
        }`
      );
      console.log(
        `     - Gas cost:    ${colors.red}${actualGasCostEth.toFixed(6)} ETH${
          colors.reset
        }`
      );
      console.log(
        `     - Total:       ${colors.red}${(
          amountEth + actualGasCostEth
        ).toFixed(6)} ETH${colors.reset}`
      );
      console.log(
        `   To change:   ${colors.green}+${toDiff.toFixed(6)} ETH${
          colors.reset
        }`
      );
      console.log("");

      // Verify calculations
      if (fromDiffMatches && toDiffMatches) {
        console.log(
          `${colors.green}✅ Balance verification passed!${colors.reset}`
        );
        console.log(
          `   Expected from change: ${expectedFromDiff.toFixed(6)} ETH`
        );
        console.log(`   Actual from change:   ${fromDiff.toFixed(6)} ETH`);
        console.log(
          `   Expected to change:   +${expectedToDiff.toFixed(6)} ETH`
        );
        console.log(`   Actual to change:     +${toDiff.toFixed(6)} ETH`);
      } else {
        console.log(
          `${colors.yellow}⚠️  Balance verification warning${colors.reset}`
        );
        if (!fromDiffMatches) {
          console.log(
            `   From change mismatch: expected ${expectedFromDiff.toFixed(
              6
            )}, got ${fromDiff.toFixed(6)}`
          );
        }
        if (!toDiffMatches) {
          console.log(
            `   To change mismatch: expected +${expectedToDiff.toFixed(
              6
            )}, got +${toDiff.toFixed(6)}`
          );
        }
        console.log(
          `   This might be due to other transactions or rounding differences.`
        );
      }
    } else {
      console.error(`${colors.red}❌ Transaction failed!${colors.reset}`);
      console.error(
        `   Status: ${colors.red}${receipt?.status}${colors.reset}`
      );
      process.exit(1);
    }
  } catch (error: any) {
    // Check if error is "already known" - transaction might already be in mempool
    if (error.message && error.message.includes("already known")) {
      console.log(
        `${colors.yellow}⚠️  Transaction already in mempool${colors.reset}`
      );
      console.log(
        `${colors.yellow}   This usually means the transaction was already sent${colors.reset}`
      );
      console.log(
        `${colors.yellow}   Waiting a moment and checking for receipt...${colors.reset}`
      );
      console.log("");

      // Try to get the transaction hash from error or check pending transactions
      // For now, just inform user and exit gracefully
      console.log(
        `${colors.blue}💡 Tip: Check pending transactions or wait for the previous transaction to be mined${colors.reset}`
      );
      process.exit(0);
    }

    console.error(`${colors.red}❌ Failed to send transaction${colors.reset}`);
    if (error.message) {
      console.error(`   Error: ${error.message}`);
    } else {
      console.error(`   Error: ${error}`);
    }
    process.exit(1);
  }

  console.log("");
  console.log(
    `${colors.blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${colors.reset}`
  );
  console.log(`${colors.green}✅ Test transaction completed!${colors.reset}`);
  console.log(
    `${colors.blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${colors.reset}`
  );
}

// Run the script
main().catch((error) => {
  console.error("Unhandled error:", error);
  process.exit(1);
});
