# Comprehensive Comparison: bera-geth vs Original geth

## Overview

**bera-geth** is Berachain's fork of go-ethereum (geth) that implements the Berachain blockchain network. While maintaining full Ethereum compatibility, it introduces several Berachain-specific features and optimizations.

---

## 1. Network Configuration

### Original geth

- **Mainnet**: Chain ID 1 (Ethereum)
- **Testnets**: Sepolia (11155111), Holesky (17000), etc.
- **Default networks**: Ethereum ecosystem

### bera-geth

- **Berachain Mainnet**: Chain ID **80094**
- **Bepolia Testnet**: Chain ID **80069**
- **Genesis Hash**: `0xd57819422128da1c44339fc7956662378c17e2213e669b427ac91cd11dfcfb38`
- **Deposit Contract**: `0x4242424242424242424242424242424242424242`

---

## 2. Base Fee Mechanism (EIP-1559)

### Original geth

- **BaseFeeChangeDenominator**: 8 (default)
- **Minimum Base Fee**: 0 wei
- **Adjustment Speed**: Standard (1/8th per block)

### bera-geth (Prague1 Fork)

- **BaseFeeChangeDenominator**: **48** (6x faster adjustment)
  - Located in: `params/protocol_params.go:138`
  - Implements **BRIP-0002**
  - Implementation: `params/config.go:1442-1460` (`BaseFeeChangeDenominator()` function)
- **Minimum Base Fee**: **1 gwei** (Prague1 Mainnet), **10 gwei** (Prague1 Bepolia Testnet), **0 wei** (Prague2+)
  - Mainnet: `params/config.go:222`
  - Bepolia Testnet: `params/config.go:282`
  - Implementation: `params/config.go:1452-1460` (`MinBaseFee()` function)
- **Adjustment Speed**: 6x faster to accommodate faster block times

**Why**: Berachain has faster block times (~6x), so base fee needs to adjust 6x faster to maintain proper fee market dynamics.

---

## 3. Proof of Liquidity (PoL) - BRIP-0004

### Original geth

- ❌ **No PoL mechanism**
- Blocks contain only user transactions

### bera-geth (Prague1+)

- ✅ **PoL Transactions** (Proof of Liquidity)
- **New Transaction Type**: `PoLTxType` (0x7E)
- **Implementation**: `core/types/tx_pol.go`

**Key Features:**

- **Automatic insertion**: PoL tx is automatically inserted as the **first transaction** in every block post-Prague1
- **No gas consumption**: PoL tx doesn't consume block gas limit
- **Gas Limit**: `30,000,000` (30M) - artificial limit for execution, not counted against block gas (`params/protocol_params.go:230`)
- **System address**: Originates from system address `0xfffffffffffffffffffffffffffffffffffffffe` (`params/protocol_params.go:208`)
- **Purpose**: Distributes rewards to validators based on liquidity provision
- **Distributor Contract**: `0xD2f19a79b026Fb636A7c300bF5947df113940761` (Prague1) (`params/protocol_params.go:231`)
- **Nonce behavior**: PoL tx nonce = `blockNumber - 1` (distributes for the previous block) (`core/types/tx_pol.go:64`)

**Block Structure:**

```
Block Transactions:
  [0] = PoL Transaction (automatic, no gas cost)
  [1..N] = User transactions (normal gas consumption)
```

**Miner Implementation**: `miner/worker.go:479-508`

- `commitPoLTx()` function automatically adds PoL tx before other transactions
- Validated in `core/block_validator.go:91-104`

---

## 4. Berachain-Specific Forks (Prague1-4)

### Original geth

- Follows Ethereum fork schedule:
  - Shanghai, Cancun, Prague, Osaka, BPO1, BPO2, Verkle
- No Berachain-specific forks

### bera-geth

- **All Ethereum forks** + **4 Berachain-specific forks**:

#### **Prague1** (Sep 03, 2025 16:00:00 UTC)

**Mục đích**: Kích hoạt Proof of Liquidity (PoL) và điều chỉnh cơ chế base fee

**Các thay đổi chính**:

1. **Kích hoạt PoL Transactions**:

   - Mỗi block sau Prague1 sẽ tự động chèn một PoL transaction ở vị trí đầu tiên
   - PoL transaction không tiêu tốn gas của block
   - PoL transaction gọi đến PoL Distributor contract để phân phối rewards cho validators
   - PoL Distributor Address: `0xD2f19a79b026Fb636A7c300bF5947df113940761`

2. **Thay đổi Base Fee Mechanism**:

   - **Minimum Base Fee**: Tăng từ 0 wei lên **1 gwei**
   - **Base Fee Change Denominator**: Tăng từ 8 lên **48** (điều chỉnh nhanh hơn 6 lần)
   - Lý do: Berachain có block time nhanh hơn ~6 lần, cần điều chỉnh base fee nhanh hơn để duy trì fee market

3. **Block Header Requirement**:
   - Yêu cầu bắt buộc: Block header phải có `ParentProposerPubkey`
   - Field này chứa public key của proposer từ block cha
   - Được sử dụng để tạo PoL transaction

**Implementation**:

- `params/config.go:219-225` - Cấu hình Prague1
- `miner/worker.go:479-508` - Logic chèn PoL transaction
- `core/block_validator.go:91-104` - Validation PoL transaction
- `consensus/beacon/consensus.go:275-285` - Validation ParentProposerPubkey

**Tác động**:

- Mỗi block có thêm 1 transaction tự động (PoL)
- Base fee không thể xuống dưới 1 gwei
- Base fee điều chỉnh nhanh hơn 6 lần khi network congestion thay đổi

**BRIP**: [BRIP-0004](https://github.com/berachain/BRIPs/blob/main/meta/BRIP-0004.md)

---

#### **Prague2** (Sep 30, 2025 16:00:00 UTC)

**Mục đích**: Điều chỉnh lại minimum base fee sau khi network đã ổn định

**Các thay đổi chính**:

1. **Loại bỏ Minimum Base Fee**:

   - **Minimum Base Fee**: Giảm từ 1 gwei về **0 wei** (như Ethereum gốc)
   - Cho phép base fee có thể xuống về 0 khi network không congestion

2. **Giữ nguyên Base Fee Adjustment Speed**:
   - **Base Fee Change Denominator**: Vẫn giữ ở **48** (điều chỉnh nhanh 6 lần)
   - Tiếp tục duy trì tốc độ điều chỉnh nhanh cho block time nhanh

**Implementation**:

- `params/config.go:226-229` - Cấu hình Prague2
- `consensus/misc/eip1559/eip1559.go` - Logic tính base fee

**Tác động**:

- Base fee có thể về 0 khi network rảnh
- Vẫn giữ tốc độ điều chỉnh nhanh (6x) khi có congestion
- Tối ưu hóa cho cả trường hợp network rảnh và đông

**Lý do**:

- Sau Prague1, network đã ổn định và có đủ dữ liệu về fee market
- Không cần minimum base fee nữa, cho phép fee market tự điều chỉnh tự nhiên hơn
- Vẫn giữ tốc độ điều chỉnh nhanh để phù hợp với block time nhanh

---

#### **Prague3** (Nov 03, 2025 10:07:39 UTC)

**Mục đích**: Bảo mật và chặn các địa chỉ bị compromise

**Các thay đổi chính**:

1. **BEX Vault Protection**:

   - **BEX Vault Address**: `0x4be03f781c497a489e3cb0287833452cA9B9E80B`
   - Chặn các transaction tương tác với BEX Vault trong giai đoạn này
   - Bảo vệ vault khỏi các tương tác không mong muốn

2. **Address Blocking**:

   - **8 địa chỉ bị chặn** không thể nhận ERC20 transfers:
     - `0x9BAD77F1D527CD2D023d33eB3597A456d0c1Ab4a`
     - `0xD875De13Dc789B070a9F2a4549fbBb94cCdA4112`
     - `0xF8Bec8cB704b8BD427FD209A2058b396C4BC543e`
     - `0xF2b63Dbf539f4862a2eA3a04520D4E04ed5b499C`
     - `0x506D1f9EFe24f0d47853aDca907EB8d89AE03207`
     - `0x045371528a01071d6e5c934d42d641fd3cbe941c`
     - `0xF8be2BF5a14f17C897d00b57fb40EcF8b96c543e`
     - `0x9BAD91648D4769695591853478E628bCb499AB4A`
   - Các địa chỉ này có thể đã bị compromise hoặc liên quan đến sự cố bảo mật

3. **Rescue Address**:

   - **Rescue Address**: `0xD276D30592bE512a418f2448e23f9E7F372b32A2`
   - Địa chỉ được sử dụng để "cứu" funds từ các địa chỉ bị chặn

4. **Transaction Validation**:
   - Reject các transaction có ERC20 transfer đến/từ các địa chỉ bị chặn
   - Reject các transaction tương tác với BEX Vault
   - Validation được thực hiện trong `ValidatePrague3Transaction()`

**Implementation**:

- `params/config.go:230-244` - Cấu hình Prague3 (blocked addresses, BEX vault, rescue address)
- `core/state_processor.go:174-179` - Gọi validation trong transaction processing
- `core/state_processor.go:243-273` - Logic `ValidatePrague3Transaction()`
  - Kiểm tra ERC20 Transfer events
  - Kiểm tra InternalBalanceChanged events từ BEX vault
  - Reject transaction nếu vi phạm

**Tác động**:

- Bảo vệ network khỏi các địa chỉ bị compromise
- Ngăn chặn funds bị chuyển đến các địa chỉ không an toàn
- Bảo vệ BEX Vault trong giai đoạn chuyển tiếp

**Lý do**:

- Phản ứng nhanh với các sự cố bảo mật
- Bảo vệ users và funds
- Temporary measure để xử lý các vấn đề bảo mật cụ thể

---

#### **Prague4** (Nov 12, 2025 16:00:00 UTC)

**Mục đích**: Gỡ bỏ các hạn chế của Prague3 sau khi vấn đề đã được xử lý

**Các thay đổi chính**:

1. **Unblock Addresses**:

   - Gỡ bỏ tất cả các hạn chế từ Prague3
   - Các địa chỉ bị chặn có thể nhận ERC20 transfers trở lại
   - BEX Vault có thể tương tác bình thường

2. **Return to Normal Operation**:
   - Network hoạt động bình thường như trước Prague3
   - Không còn validation đặc biệt cho blocked addresses

**Implementation**:

- `params/config.go:245-247` - Cấu hình Prague4
- `core/state_processor.go:174-179` - Validation chỉ chạy khi trong Prague3 (không chạy sau Prague4)

**Tác động**:

- Network trở lại trạng thái bình thường
- Tất cả addresses có thể hoạt động tự do
- BEX Vault hoạt động bình thường

**Lý do**:

- Sau khi vấn đề bảo mật đã được xử lý
- Funds đã được rescue về địa chỉ an toàn
- Không cần hạn chế nữa, cho phép network hoạt động tự do

---

## 5. Block Validation

### Original geth

- Standard Ethereum block validation
- Validates: transactions, receipts, state root, gas used

### bera-geth

- **All standard validation** +
- **PoL Transaction Validation** (`core/block_validator.go:91-104`):
  - Verifies PoL tx is first transaction in Prague1+ blocks
  - Validates PoL tx structure and distributor address
  - Ensures PoL tx doesn't consume block gas
- **Prague3 Validation** (`core/state_processor.go:174-179`):
  - Validates ERC20 transfers don't involve blocked addresses
  - Rejects transactions with BEX vault interactions (Prague3 only)

---

## 6. Transaction Processing

### Original geth

- Standard transaction execution
- Gas accounting: all transactions consume block gas

### bera-geth

- **PoL Transaction Handling** (`miner/worker.go:352-356`):
  - PoL transactions **do not consume block gas**
  - Special handling in `applyTransaction()` to exclude PoL tx from gas accounting
- **Prague3 Post-Processing**:
  - Validates transaction receipts for blocked address interactions
  - Rejects invalid transactions before state finalization

---

## 7. Consensus & Block Production

### Original geth

- Proof-of-Stake (Beacon chain)
- Standard block production

### bera-geth

- **Same consensus mechanism** (Proof-of-Stake)
- **Enhanced block production**:
  - Automatic PoL tx insertion in every block (Prague1+)
  - PoL tx always at index 0
  - Faster base fee adjustments for faster block times

---

## 8. Gas & Fee Structure

### Original geth

- Base fee: Adjusts by 1/8th per block
- Minimum: 0 wei
- Standard EIP-1559 mechanics

### bera-geth

- **Base fee**: Adjusts by **1/48th per block** (6x faster)
- **Minimum**: 1 gwei (Prague1), 0 wei (Prague2+)
- **PoL tx**: No gas cost (free transaction)
- **Optimized for**: ~6x faster block times

---

## 9. State & Storage

### Original geth

- Standard Ethereum state management
- Merkle/Patricia trie
- Path-based state scheme (PBSS)

### bera-geth

- **Identical state management**
- Same trie structures
- Same PBSS implementation
- **Additional state**: PoL distributor contract state

---

## 10. EVM & Smart Contracts

### Original geth

- Standard EVM implementation
- All Ethereum opcodes
- Standard precompiles

### bera-geth

- **100% EVM compatible**
- Same opcodes and precompiles
- **Additional contracts**:
  - PoL Distributor contract (Prague1+)
  - BEX Vault contract (Prague3+)

---

## 11. Network & P2P

### Original geth

- Ethereum mainnet bootnodes
- Standard P2P protocol

### bera-geth

- **Berachain-specific bootnodes** (`params/bootnodes.go:59-136`)
- Same P2P protocol (Ethereum-compatible)
- Different network ID (80094)

---

## 12. RPC & APIs

### Original geth

- Standard JSON-RPC APIs
- eth, net, web3, debug, txpool

### bera-geth

- **Identical RPC APIs**
- Full Ethereum JSON-RPC compatibility
- Same API endpoints and methods

---

## 13. Code Structure Differences

### Key Files Modified/Added:

1. **`params/config.go`**:

   - Added `BerachainChainConfig` and `BepoliaChainConfig`
   - Added `BerachainConfig` with Prague1-4 configurations
   - Modified base fee calculation methods

2. **`params/protocol_params.go`**:

   - Added `BerachainBaseFeeChangeDenominator = 48`
   - Added `PoLDistributorAddress`

3. **`core/types/tx_pol.go`** (NEW):

   - PoL transaction type implementation
   - PoL transaction encoding/decoding

4. **`miner/worker.go`**:

   - Added `commitPoLTx()` function
   - Modified `applyTransaction()` for PoL tx gas handling

5. **`core/block_validator.go`**:

   - Added PoL tx validation logic

6. **`core/state_processor.go`**:

   - Added `ValidatePrague3Transaction()` function
   - Modified transaction processing for Prague3 validation

7. **`cmd/utils/flags.go`**:

   - Added `BerachainFlag` and `BepoliaFlag`
   - Added to `NetworkFlags`

8. **`cmd/bera-geth/main.go`**:
   - Added Berachain network detection and logging

---

## 14. Performance Optimizations

### Original geth

- Standard cache defaults (1024 MB)
- Standard sync modes

### bera-geth

- **Enhanced cache defaults**:
  - Mainnet default: **4096 MB** (4x increase)
  - Optimized for Berachain's faster block times
- Same sync modes (snap, full, etc.)

---

## 15. Genesis & Chain Initialization

### Original geth

- Ethereum mainnet genesis
- Standard allocation

### bera-geth

- **Berachain-specific genesis**:
  - Chain ID: 80094
  - Custom allocations
  - All pre-merge forks at block 0
  - Post-merge from genesis (timestamp-based forks)
- **Implementation**: `core/genesis.go:676-687`

---

## 16. Transaction Types

### Original geth

- Legacy (0x00)
- EIP-1559 (0x02)
- EIP-2930 (0x01)
- Blob (0x03)

### bera-geth

- **All Ethereum types** +
- **PoL Transaction (0x7E)**:
  - System-generated
  - No signature required
  - No gas cost
  - Always first in block (Prague1+)

---

## 17. Blob Transaction Configuration (EIP-4844)

### Original geth

- **Prague Blob Config**:
  - Target: **6** blobs per block
  - Max: **9** blobs per block
  - UpdateFraction: **5007716**
- Standard blob capacity

### bera-geth

- **Berachain Prague Blob Config** (`params/config.go:491-495`):
  - Target: **3** blobs per block (50% of standard)
  - Max: **6** blobs per block (67% of standard)
  - UpdateFraction: **3338477** (different adjustment rate)
- **Lower blob capacity** optimized for Berachain's faster block times
- **Implementation**: `DefaultBerachainPragueBlobConfig`

**Why**: With ~6x faster block times, lower blob capacity per block maintains similar overall throughput while optimizing for faster block production.

---

## 18. Transaction Pool Behavior

### Original geth

- All valid transaction types can be submitted to the pool
- Standard transaction validation and acceptance

### bera-geth

- **PoL Transaction Rejection** (`core/txpool/txpool.go:328-330`):
  - PoL transactions are **explicitly rejected** from the transaction pool
  - Users cannot submit PoL transactions (they're system-generated only)
  - Prevents malicious or accidental PoL tx submissions
- All other transaction types behave identically

---

## Summary Table

| Aspect                    | Original geth | bera-geth                                                         |
| ------------------------- | ------------- | ----------------------------------------------------------------- |
| **Chain ID**              | 1 (mainnet)   | 80094 (mainnet)                                                   |
| **Base Fee Denominator**  | 8             | 48 (6x faster)                                                    |
| **Min Base Fee**          | 0 wei         | 1 gwei (Prague1 Mainnet), 10 gwei (Prague1 Bepolia), 0 (Prague2+) |
| **PoL Transactions**      | ❌ No         | ✅ Yes (Prague1+)                                                 |
| **Block Gas for PoL**     | N/A           | 0 (free)                                                          |
| **Berachain Forks**       | ❌ No         | ✅ Prague1-4                                                      |
| **Address Blocking**      | ❌ No         | ✅ Yes (Prague3)                                                  |
| **BEX Vault**             | ❌ No         | ✅ Yes (Prague3)                                                  |
| **Blob Target (Prague)**  | 6             | 3 (50% of standard)                                               |
| **Blob Max (Prague)**     | 9             | 6 (67% of standard)                                               |
| **Tx Pool PoL Rejection** | ❌ No         | ✅ Yes (PoL txs rejected)                                         |
| **Block Header Fields**   | Standard      | + ParentProposerPubkey (Prague1+)                                 |
| **Database Schema**       | ✅ Standard   | ✅ Identical (no changes)                                         |
| **Storage Format**        | ✅ Standard   | ✅ Identical (no changes)                                         |
| **EVM Compatibility**     | ✅ Full       | ✅ 100% Compatible                                                |
| **RPC APIs**              | ✅ Standard   | ✅ Identical                                                      |
| **Consensus**             | PoS           | PoS (same)                                                        |
| **Default Cache**         | 1024 MB       | 4096 MB (mainnet)                                                 |

---

## 19. Block Header Structure

### Original geth

- **Standard Header Fields**:
  - ParentHash, UncleHash, Coinbase, Root, TxHash, ReceiptHash, Bloom
  - Difficulty, Number, GasLimit, GasUsed, Time, Extra, MixDigest, Nonce
  - BaseFee (EIP-1559), WithdrawalsHash (EIP-4895)
  - BlobGasUsed, ExcessBlobGas (EIP-4844)
  - ParentBeaconRoot (EIP-4788), RequestsHash (EIP-7685)
- **No proposer pubkey field**

### bera-geth

- **All standard header fields** +
- **ParentProposerPubkey** (`core/types/block.go:110-111`):
  - **New Field**: `ParentProposerPubkey *common.Pubkey` (BRIP-0004)
  - **Purpose**: Stores the proposer's public key from the parent block
  - **Required**: Must be present in Prague1+ blocks, must be nil before Prague1
  - **Validation**: Enforced in `consensus/beacon/consensus.go:275-285`
  - **Usage**: Used to generate PoL transactions that distribute rewards to validators
  - **RLP Encoding**: Optional field (backward compatible)

**Implementation Details**:

- Header validation checks for presence/absence based on Prague1 activation
- Payload building includes proposer pubkey in `miner/payload_building.go:46`
- Genesis block sets `ParentProposerPubkey` to zero pubkey (`core/genesis.go:545-548`)

---

## 20. Database & Storage Format

### Original geth

- **Database Schema**: Standard Ethereum key-value database
- **Storage Engine**: LevelDB/Pebble (key-value store)
- **Key Prefixes**: Standard prefixes (h=header, b=body, r=receipts, l=tx lookup, etc.)
- **State Storage**: Merkle/Patricia trie nodes, contract code, account state
- **Block Storage**: Headers, bodies, receipts stored with standard prefixes
- **Schema Location**: `core/rawdb/schema.go`

### bera-geth

- **Identical Database Schema**: No changes to database structure
- **Same Storage Engine**: LevelDB/Pebble (same implementation)
- **Same Key Prefixes**: All standard Ethereum prefixes unchanged
- **Same Storage Format**:
  - PoL transactions stored in blocks using standard block body format
  - PoL distributor contract state stored in state trie (standard contract storage)
  - No custom database tables or schemas
- **No Migration Required**: Database format is 100% compatible

**Key Points**:

- PoL transactions are stored as regular transactions in block bodies (using standard `blockBodyPrefix`)
- PoL distributor contract state uses standard contract storage (no special handling)
- All Berachain-specific data uses existing Ethereum storage mechanisms
- Database can be inspected/queried using standard geth tools

---

## Key Takeaways

1. **Full Ethereum Compatibility**: bera-geth maintains 100% EVM and JSON-RPC compatibility
2. **PoL Integration**: Unique Proof of Liquidity mechanism for validator rewards
3. **Faster Fee Market**: 6x faster base fee adjustments for faster block times
4. **Security Features**: Address blocking and BEX vault protection (Prague3)
5. **Backward Compatible**: All Ethereum tools and contracts work on Berachain
6. **Optimized Performance**: Enhanced caching for faster block processing

---

## Complete Summary of All Berachain Changes

### **Core Protocol Changes (BRIPs)**

#### **1. BRIP-0002: Base Fee Mechanism**

- **What Changed**: Base fee adjustment speed increased 6x
- **Why**: Berachain has ~6x faster block times, so fee market needs to adjust faster
- **Implementation**:
  - `BaseFeeChangeDenominator`: 8 → **48** (6x faster)
  - `MinimumBaseFeeWei`: 0 wei → **1 gwei** (Prague1 Mainnet), **10 gwei** (Prague1 Bepolia Testnet), then back to 0 (Prague2+)
- **Location**: `params/protocol_params.go:138`, `params/config.go:1442-1460`
- **Impact**: Base fee responds 6x faster to network congestion, maintaining proper fee dynamics

#### **2. BRIP-0004: Proof of Liquidity (PoL)**

- **What Changed**: New transaction type automatically inserted in every block
- **Why**: Distribute rewards to validators based on liquidity provision
- **Implementation**:
  - New transaction type: `PoLTxType` (0x7E)
  - Automatically inserted as **first transaction** in every block (Prague1+)
  - **No gas consumption** - doesn't count against block gas limit
  - **Gas Limit**: 30,000,000 (30M) - artificial limit for execution only (`params/protocol_params.go:230`)
  - Originates from system address: `0xfffffffffffffffffffffffffffffffffffffffe`
  - Calls PoL Distributor: `0xD2f19a79b026Fb636A7c300bF5947df113940761`
  - **Nonce**: `blockNumber - 1` (distributes for the previous block)
- **Location**: `core/types/tx_pol.go` (new file), `miner/worker.go:479-508`
- **Impact**: Every block includes a PoL transaction that distributes rewards, enabling Berachain's liquidity-based consensus

### **Network Configuration Changes**

#### **3. New Networks**

- **Berachain Mainnet**: Chain ID **80094**
  - Genesis Hash: `0xd57819422128da1c44339fc7956662378c17e2213e669b427ac91cd11dfcfb38`
  - Deposit Contract: `0x4242424242424242424242424242424242424242`
- **Bepolia Testnet**: Chain ID **80069**
- **Location**: `params/config.go:190-249`, `params/bootnodes.go:59-136`
- **Impact**: Separate blockchain networks with their own genesis and bootnodes

### **Berachain-Specific Forks**

#### **4. Prague1 Fork** (Sep 03, 2025)

- **Purpose**: Enable PoL + base fee changes
- **Changes**:
  - Enables PoL transactions
  - Sets minimum base fee to 1 gwei
  - Base fee change denominator = 48
  - PoL Distributor address configured
- **Location**: `params/config.go:219-225`

#### **5. Prague2 Fork** (Sep 30, 2025)

- **Purpose**: Base fee adjustments
- **Changes**:
  - Removes minimum base fee (back to 0 wei)
  - Keeps faster adjustment (denominator = 48)
- **Location**: `params/config.go:226-229`

#### **6. Prague3 Fork** (Nov 03, 2025)

- **Purpose**: Security and address blocking
- **Changes**:
  - BEX Vault Address: `0x4be03f781c497a489e3cb0287833452cA9B9E80B`
  - 8 blocked addresses (cannot receive ERC20 transfers)
  - Rescue Address: `0xD276D30592bE512a418f2448e23f9E7F372b32A2`
  - Validates and rejects transactions with blocked address interactions
- **Location**: `params/config.go:230-244`, `core/state_processor.go:243-273`
- **Impact**: Security measure to prevent certain address interactions

#### **7. Prague4 Fork** (Nov 12, 2025)

- **Purpose**: Remove Prague3 restrictions
- **Changes**: Unblocks addresses (Prague3 restrictions removed)
- **Location**: `params/config.go:245-247`

### **Block Structure Changes**

#### **8. Block Header Enhancement**

- **New Field**: `ParentProposerPubkey *common.Pubkey`
- **Purpose**: Stores proposer's public key from parent block (required for PoL)
- **Requirements**:
  - Must be present in Prague1+ blocks
  - Must be nil before Prague1
- **Location**: `core/types/block.go:110-111`, `consensus/beacon/consensus.go:275-285`
- **Impact**: Enables PoL transaction generation using parent block's proposer pubkey

### **Transaction Processing Changes**

#### **9. PoL Transaction Handling**

- **Gas Accounting**: PoL transactions don't consume block gas
- **Automatic Insertion**: Miner automatically adds PoL tx before user transactions
- **Validation**: Block validator ensures PoL tx is first and correctly formatted
- **Location**: `miner/worker.go:352-356`, `core/block_validator.go:91-104`
- **Impact**: PoL transactions are "free" and don't reduce available block gas

#### **10. Prague3 Transaction Validation**

- **ERC20 Transfer Blocking**: Rejects transfers to/from blocked addresses
- **BEX Vault Protection**: Rejects transactions with BEX vault interactions (Prague3 only)
- **Location**: `core/state_processor.go:174-179`, `core/state_processor.go:243-273`
- **Impact**: Security measure enforced at transaction processing level

### **Transaction Pool Changes**

#### **11. PoL Transaction Rejection**

- **Behavior**: PoL transactions are explicitly rejected from transaction pool
- **Why**: PoL transactions are system-generated only, users cannot submit them
- **Location**: `core/txpool/txpool.go:328-330`
- **Impact**: Prevents malicious or accidental PoL tx submissions

### **Blob Transaction Configuration**

#### **12. Lower Blob Capacity**

- **Prague Blob Config**:
  - Target: 6 → **3** blobs per block (50% reduction)
  - Max: 9 → **6** blobs per block (33% reduction)
  - UpdateFraction: 5007716 → **3338477**
- **Why**: Optimized for faster block times while maintaining throughput
- **Location**: `params/config.go:491-495`
- **Impact**: Lower blob capacity per block, but faster blocks maintain overall throughput

### **Performance Optimizations**

#### **13. Enhanced Cache Defaults**

- **Mainnet Cache**: 1024 MB → **4096 MB** (4x increase)
- **Why**: Optimized for Berachain's faster block times
- **Location**: `eth/ethconfig/config.go` (implicit via chain config)
- **Impact**: Better performance for faster block processing

### **Code Structure Changes**

#### **14. New Files**

- `core/types/tx_pol.go` - PoL transaction type implementation
- `core/types/tx_pol_test.go` - PoL transaction tests

#### **15. Modified Files**

- `params/config.go` - Added Berachain chain configs and fork schedules
- `params/protocol_params.go` - Added Berachain constants
- `params/bootnodes.go` - Added Berachain bootnodes
- `miner/worker.go` - Added PoL tx insertion logic
- `core/block_validator.go` - Added PoL tx validation
- `core/state_processor.go` - Added Prague3 validation
- `core/types/block.go` - Added ParentProposerPubkey field
- `core/types/transaction.go` - Added PoLTxType constant
- `consensus/beacon/consensus.go` - Added ParentProposerPubkey validation
- `cmd/utils/flags.go` - Added --berachain and --bepolia flags
- `cmd/bera-geth/main.go` - Added network detection and logging
- `core/txpool/txpool.go` - Added PoL tx rejection
- `miner/payload_building.go` - Added proposer pubkey to payload args
- `beacon/engine/types.go` - Added proposer pubkey to engine types
- `internal/ethapi/` - Updated to use Berachain config for transaction creation



### **What Remains Identical**

✅ **EVM**: 100% compatible, all opcodes and precompiles identical  
✅ **JSON-RPC APIs**: All endpoints and methods identical  
✅ **Database Schema**: Same key-value structure, no changes  
✅ **State Management**: Same trie structures (Merkle/Patricia/Verkle)  
✅ **Consensus Mechanism**: Same Proof-of-Stake (Beacon chain)  
✅ **P2P Protocol**: Same Ethereum-compatible networking  
✅ **Transaction Types**: All Ethereum types (Legacy, EIP-1559, EIP-2930, Blob) work identically  
✅ **Smart Contracts**: All Ethereum contracts work without modification

### **Migration Impact**

- **For Users**: No changes needed - all Ethereum tools work
- **For Developers**: Can use existing Ethereum development tools
- **For Contracts**: All existing contracts work without modification
- **For Nodes**: Need to use bera-geth binary (not standard geth) for Berachain networks

### **Why These Changes?**

1. **Faster Block Times**: Berachain has ~6x faster blocks, requiring faster fee adjustments
2. **Liquidity-Based Consensus**: PoL mechanism rewards validators based on liquidity provision
3. **Security**: Prague3 address blocking provides additional security measures
4. **Optimization**: Lower blob capacity and higher cache optimize for faster blocks
5. **Compatibility**: All changes maintain 100% Ethereum compatibility

---

## Code Verification Status

### Implementation Verification: ✅ **ALL FEATURES VERIFIED**

All documented differences from Ethereum geth have been verified against the source code:

- ✅ **Network Configuration**: Chain IDs, genesis hash, deposit contract - All verified
- ✅ **Base Fee Mechanism**: BaseFeeChangeDenominator (48), MinBaseFee functions - All verified
- ✅ **PoL Implementation**: Transaction type, insertion logic, gas handling - All verified
- ✅ **Prague Forks**: All fork timestamps and configurations - All verified
- ✅ **Block Header**: ParentProposerPubkey field and validation - All verified
- ✅ **Block Validation**: PoL validation and Prague3 checks - All verified
- ✅ **Transaction Processing**: PoL gas handling and Prague3 validation - All verified
- ✅ **Transaction Pool**: PoL tx rejection - All verified
- ✅ **Blob Configuration**: Lower blob capacity - All verified
- ✅ **Performance**: Cache optimization - All verified

### Code References

**Key Implementation Files:**

- `params/config.go` - Chain configurations, fork schedules, base fee functions
- `params/protocol_params.go` - Constants (BaseFeeChangeDenominator, PoL addresses)
- `core/types/tx_pol.go` - PoL transaction type implementation (NEW FILE)
- `core/types/block.go` - ParentProposerPubkey field
- `miner/worker.go` - PoL tx insertion (`commitPoLTx()`)
- `core/block_validator.go` - PoL tx validation
- `core/state_processor.go` - Prague3 transaction validation
- `core/txpool/txpool.go` - PoL tx rejection
- `consensus/beacon/consensus.go` - ParentProposerPubkey validation
- `core/genesis.go` - Genesis block ParentProposerPubkey initialization

### Additional Implementation Details

1. **Genesis Block ParentProposerPubkey**: Set to zero pubkey for genesis block (`core/genesis.go:544-548`)
2. **Prague Fork Dependencies**: All Prague1-4 forks require Ethereum's Prague fork to be active first (`params/config.go:1084, 1090, 1096, 1102`)
3. **State Transition**: PoL transactions are flagged with `IsPoLTx` flag for proper gas accounting (`core/state_transition.go:195`)

---

## Known Issues & Recommendations

### 🔴 Critical Issues: None

### 🟡 Minor Issues: None (All resolved)

**Previously Found Issues (Now Fixed):**

- ✅ Error message inconsistency in Prague3 validation (fixed: changed "blob transaction" to "transaction")

### 📝 Documentation Notes

1. **Bepolia Testnet Differences**: Bepolia testnet uses 10 gwei minimum base fee in Prague1 (vs 1 gwei for mainnet) - now documented above
2. **PoLTxGasLimit**: Value of 30,000,000 is now documented in PoL section
3. **PoL Nonce Behavior**: Nonce semantics (blockNumber - 1) now documented

---

## References

- **BRIP-0002**: Base Fee Change Denominator
- **BRIP-0004**: Proof of Liquidity (PoL) - https://github.com/berachain/BRIPs/blob/main/meta/BRIP-0004.md
- **Berachain Documentation**: https://docs.berachain.com
- **Berachain GitHub**: https://github.com/berachain
