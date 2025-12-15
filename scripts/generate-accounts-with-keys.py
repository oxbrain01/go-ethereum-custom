#!/usr/bin/env python3
"""
Script để generate 5 Ethereum accounts với private keys để import MetaMask
Sử dụng accounts mặc định từ default-test-accounts.json nếu có
"""

import json
import os
import secrets

# Check if default accounts file exists
DEFAULT_ACCOUNTS_FILE = "scripts/default-test-accounts.json"
TEST_ACCOUNTS_FILE = "scripts/test-accounts.json"

# Use default accounts if they exist
if os.path.exists(DEFAULT_ACCOUNTS_FILE):
    print("📋 Using default test accounts from default-test-accounts.json")
    with open(DEFAULT_ACCOUNTS_FILE, "r") as f:
        default_data = json.load(f)
        accounts = default_data["accounts"]
    print(f"✅ Loaded {len(accounts)} default accounts")
else:
    # Generate new accounts
    print("📝 Generating new test accounts...")
    try:
        from eth_account import Account
        Account.enable_unaudited_hdwallet_features()
        USE_ETH_ACCOUNT = True
    except ImportError:
        USE_ETH_ACCOUNT = False
        print("⚠️  eth-account not installed. Installing...")
        import subprocess
        import sys
        subprocess.check_call([sys.executable, "-m", "pip", "install", "eth-account", "--quiet"])
        from eth_account import Account
        Account.enable_unaudited_hdwallet_features()
        USE_ETH_ACCOUNT = True

    def generate_account():
        """Generate a random Ethereum account with proper secp256k1"""
        # Generate 32 random bytes (256 bits) for private key
        private_key_bytes = secrets.token_bytes(32)
        private_key_hex = '0x' + private_key_bytes.hex()
        
        # Use eth_account to derive address from private key (proper secp256k1)
        account = Account.from_key(private_key_hex)
        
        return {
            "address": account.address,
            "privateKey": private_key_hex,
        }

    # Generate 5 accounts
    accounts = []
    for i in range(1, 6):
        account = generate_account()
        account["password"] = f"test{i}"
        account["balance"] = "50 ETH"
        accounts.append(account)
        print(f"Account {i}: {account['address']}")

# Save to JSON (only if using default accounts or if test-accounts.json doesn't exist)
if not os.path.exists(TEST_ACCOUNTS_FILE) or os.path.exists(DEFAULT_ACCOUNTS_FILE):
    output = {
        "accounts": accounts
    }
    
    with open(TEST_ACCOUNTS_FILE, "w") as f:
        json.dump(output, f, indent=2)
    
    if os.path.exists(DEFAULT_ACCOUNTS_FILE):
        print(f"\n✅ Loaded {len(accounts)} default accounts")
    else:
        print(f"\n✅ Generated {len(accounts)} accounts")
    print(f"📄 Saved to: {TEST_ACCOUNTS_FILE}")
else:
    print(f"\n✅ Using existing accounts from {TEST_ACCOUNTS_FILE}")
    with open(TEST_ACCOUNTS_FILE, "r") as f:
        existing_data = json.load(f)
        accounts = existing_data["accounts"]

# Update genesis file
try:
    with open("scripts/genesis-2-validators.json", "r") as f:
        genesis = json.load(f)
    
    if "alloc" not in genesis:
        genesis["alloc"] = {}
    
    # Add 50 ETH for each account
    for acc in accounts:
        genesis["alloc"][acc["address"]] = {
            "balance": "50000000000000000000"  # 50 ETH in wei
        }
    
    with open("scripts/genesis-2-validators.json", "w") as f:
        json.dump(genesis, f, indent=2)
    
    print("✅ Updated genesis file")
except Exception as e:
    print(f"⚠️  Could not update genesis file: {e}")

print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("📋 ACCOUNTS GENERATED:")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
for i, acc in enumerate(accounts, 1):
    print(f"\nAccount {i}:")
    print(f"  Address:    {acc['address']}")
    print(f"  PrivateKey: {acc['privateKey']}")
    print(f"  Password:   {acc['password']}")
    print(f"  Balance:    {acc['balance']}")

print("\n💡 To import into MetaMask:")
print("   1. Open MetaMask")
print("   2. Click account menu → Import Account")
print("   3. Paste the private key from above")

