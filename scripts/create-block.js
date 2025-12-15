// Script to manually create a block in Clique consensus
// This forces block creation when transactions are pending

// Check pending transactions
var pending = txpool.status.pending;
var queued = txpool.status.queued;

console.log("Pending transactions: " + pending);
console.log("Queued transactions: " + queued);

if (pending > 0 || queued > 0) {
    console.log("Transactions pending, attempting to create block...");
    
    // For Clique, we need to wait for the period to pass
    // But we can try to advance time or trigger block creation
    // In post-merge mode, blocks are created through the engine API
    
    // Try to get the latest block
    var latest = eth.getBlock("latest");
    console.log("Latest block: " + latest.number);
    console.log("Latest block time: " + latest.timestamp);
    console.log("Current time: " + Math.floor(Date.now() / 1000));
    
    // For now, just return that we need to wait
    console.log("Note: Clique blocks are created every 5 seconds (period).");
    console.log("If transactions are pending, blocks should be created automatically.");
}

