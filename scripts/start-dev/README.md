# Development Start Script

This script starts a Geth node in development mode with comprehensive trace logging enabled.

## Features

- **Development Mode**: Automatic block creation every 5 seconds
- **Trace Logging**: Maximum verbosity (level 5) with detailed module logging
- **VM Debugging**: VM debug mode enabled for contract execution tracing
- **Dual Output**: Logs displayed in terminal and saved to log files
- **Full API Access**: All RPC APIs enabled including debug and trace

## Usage

```bash
./scripts/start-dev/start-dev.sh
```

## Configuration

- **HTTP RPC**: `http://localhost:8545`
- **WebSocket RPC**: `ws://localhost:8546`
- **Auth RPC**: `http://localhost:8551`
- **P2P Port**: `30303`
- **Network ID**: `1337`

## Logging

- **Verbosity Level**: 5 (maximum detail)
- **Module Verbosity**: 
  - `eth/*=5` - Ethereum protocol
  - `core/*=5` - Core blockchain
  - `consensus/*=5` - Consensus engine
  - `state/*=5` - State management
  - `vm/*=5` - Virtual machine
  - `txpool/*=5` - Transaction pool
  - `miner/*=5` - Mining operations

- **Log Files**: Saved to `scripts/start-dev/logs/` with timestamps
- **Log Format**: Terminal (colored) output, also saved to file

## Data Directory

Blockchain data is stored in `scripts/start-dev/data/`

## Stopping the Node

Press `Ctrl+C` to gracefully shutdown the node.

## Development Account

In dev mode, a pre-funded developer account is automatically available:
- **Private Key**: `0xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291`
- **Address**: Automatically unlocked and pre-funded

## Example: Viewing Logs

```bash
# View latest log file
tail -f scripts/start-dev/logs/geth-*.log

# Search for specific patterns
grep "TRACE" scripts/start-dev/logs/geth-*.log
```

