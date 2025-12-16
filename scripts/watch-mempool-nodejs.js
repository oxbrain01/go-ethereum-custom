#!/usr/bin/env node
/**
 * Real-time mempool monitor using WebSocket subscription
 * This catches transactions immediately when they arrive
 * 
 * Usage: node watch-mempool-nodejs.js
 * Or: chmod +x watch-mempool-nodejs.js && ./watch-mempool-nodejs.js
 */

const WebSocket = require('ws');
const http = require('http');

const WS_URL = process.env.WS_URL || 'ws://localhost:8547';
const HTTP_URL = process.env.HTTP_URL || 'http://localhost:8546';

let detectionCount = 0;

function getMempoolStatus() {
    return new Promise((resolve, reject) => {
        const data = JSON.stringify({
            jsonrpc: '2.0',
            method: 'txpool_status',
            params: [],
            id: 1
        });

        const options = {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': data.length
            }
        };

        const req = http.request(HTTP_URL, options, (res) => {
            let body = '';
            res.on('data', (chunk) => { body += chunk; });
            res.on('end', () => {
                try {
                    const result = JSON.parse(body);
                    const pending = parseInt(result.result.pending, 16);
                    const queued = parseInt(result.result.queued, 16);
                    resolve({ pending, queued });
                } catch (e) {
                    reject(e);
                }
            });
        });

        req.on('error', reject);
        req.write(data);
        req.end();
    });
}

function getTransactionDetails(txHash) {
    return new Promise((resolve, reject) => {
        const data = JSON.stringify({
            jsonrpc: '2.0',
            method: 'eth_getTransactionByHash',
            params: [txHash],
            id: 1
        });

        const options = {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': data.length
            }
        };

        const req = http.request(HTTP_URL, options, (res) => {
            let body = '';
            res.on('data', (chunk) => { body += chunk; });
            res.on('end', () => {
                try {
                    const result = JSON.parse(body);
                    resolve(result.result);
                } catch (e) {
                    reject(e);
                }
            });
        });

        req.on('error', reject);
        req.write(data);
        req.end();
    });
}

console.log('📊 Real-Time Mempool Monitor (WebSocket)');
console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
console.log(`🔌 WebSocket: ${WS_URL}`);
console.log(`🌐 HTTP RPC: ${HTTP_URL}`);
console.log('💡 Subscribing to newPendingTransactions...');
console.log('💡 Press Ctrl+C to stop');
console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
console.log('');

const ws = new WebSocket(WS_URL);

ws.on('open', () => {
    console.log('✅ Connected to WebSocket');
    
    // Subscribe to new pending transactions
    const subscribeMsg = {
        jsonrpc: '2.0',
        id: 1,
        method: 'eth_subscribe',
        params: ['newPendingTransactions']
    };
    
    ws.send(JSON.stringify(subscribeMsg));
    console.log('📡 Subscription sent, waiting for transactions...\n');
});

ws.on('message', async (data) => {
    try {
        const message = JSON.parse(data.toString());
        
        // Handle subscription confirmation
        if (message.result && typeof message.result === 'string') {
            console.log(`✅ Subscribed! Subscription ID: ${message.result}\n`);
            return;
        }
        
        // Handle transaction notifications
        if (message.params && message.params.result) {
            detectionCount++;
            const txHash = message.params.result;
            const timestamp = new Date().toLocaleTimeString('en-US', { 
                hour12: false, 
                hour: '2-digit', 
                minute: '2-digit', 
                second: '2-digit',
                fractionalSecondDigits: 3
            });
            
            console.log(`🔔 TRANSACTION DETECTED! #${detectionCount} [${timestamp}]`);
            console.log(`   Hash: ${txHash}`);
            
            // Get transaction details
            try {
                const txDetails = await getTransactionDetails(txHash);
                if (txDetails) {
                    console.log(`   From: ${txDetails.from || 'N/A'}`);
                    console.log(`   To: ${txDetails.to || 'Contract Creation'}`);
                    const value = BigInt(txDetails.value || '0x0');
                    console.log(`   Value: ${Number(value) / 1e18} ETH`);
                    console.log(`   Gas: ${parseInt(txDetails.gas || '0x0', 16)}`);
                }
            } catch (e) {
                // Transaction might be mined already
            }
            
            // Get mempool status
            try {
                const status = await getMempoolStatus();
                console.log(`   📊 Mempool: ${status.pending} pending, ${status.queued} queued`);
            } catch (e) {
                // Ignore
            }
            
            console.log('');
        }
    } catch (e) {
        console.error('⚠️  Error processing message:', e.message);
    }
});

ws.on('error', (error) => {
    console.error('❌ WebSocket error:', error.message);
    console.error('💡 Make sure WebSocket is enabled in geth (--ws flag)');
    process.exit(1);
});

ws.on('close', () => {
    console.log('\n👋 WebSocket connection closed');
    process.exit(0);
});

// Handle Ctrl+C
process.on('SIGINT', () => {
    console.log('\n👋 Stopping...');
    ws.close();
    process.exit(0);
});

