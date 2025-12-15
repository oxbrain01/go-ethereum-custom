#!/usr/bin/env python3
"""
Beacon Simulator for Clique consensus in post-merge mode
This simulates a beacon client that triggers block creation via Engine API
"""

import requests
import time
import json
import os
import hmac
import hashlib

RPC_URL = "http://localhost:8546"
AUTH_PORT = 8551
AUTH_URL = f"http://localhost:{AUTH_PORT}"
JWT_SECRET_PATH = os.path.expanduser("~/local-blockchain/geth/jwtsecret")
PERIOD = 5  # Clique period in seconds

def read_jwt_secret():
    """Read JWT secret from file"""
    try:
        with open(JWT_SECRET_PATH, 'rb') as f:
            content = f.read()
            # Try to decode as hex string first
            try:
                return content.decode('utf-8').strip()
            except:
                # If not valid UTF-8, return as hex
                return content.hex()
    except FileNotFoundError:
        print(f"❌ JWT secret not found at {JWT_SECRET_PATH}")
        return None

def generate_jwt_token(secret_str):
    """Generate JWT token for Engine API authentication"""
    secret_clean = secret_str.strip()
    # Remove 0x prefix if present
    if secret_clean.startswith('0x'):
        secret_clean = secret_clean[2:]
    
    try:
        import jwt
        # JWT secret can be hex or raw string - try both
        try:
            secret_bytes = bytes.fromhex(secret_clean)
        except ValueError:
            # Not hex, treat as raw string
            secret_bytes = secret_clean.encode('utf-8')
        
        payload = {"iat": int(time.time())}
        token = jwt.encode(payload, secret_bytes, algorithm="HS256")
        return token
    except ImportError:
        # Fallback: simple JWT generation
        import base64
        header = {"alg": "HS256", "typ": "JWT"}
        payload = {"iat": int(time.time())}
        
        header_b64 = base64.urlsafe_b64encode(json.dumps(header).encode()).decode().rstrip('=')
        payload_b64 = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip('=')
        
        message = f"{header_b64}.{payload_b64}"
        try:
            secret_bytes = bytes.fromhex(secret_clean)
        except ValueError:
            secret_bytes = secret_clean.encode('utf-8')
        
        signature = hmac.new(secret_bytes, message.encode(), hashlib.sha256).digest()
        sig_b64 = base64.urlsafe_b64encode(signature).decode().rstrip('=')
        
        return f"{header_b64}.{payload_b64}.{sig_b64}"

def get_head_block():
    """Get current head block"""
    try:
        response = requests.post(RPC_URL, json={
            "jsonrpc": "2.0",
            "method": "eth_getBlockByNumber",
            "params": ["latest", False],
            "id": 1
        }, timeout=2)
        result = response.json()
        if 'result' in result and result['result']:
            return result['result']['hash'], int(result['result']['number'], 16)
        return None, 0
    except Exception as e:
        print(f"Error getting head block: {e}")
        return None, 0

def forkchoice_updated(head_hash, jwt_token=None, timestamp=None):
    """Call ForkchoiceUpdated to trigger block creation"""
    if timestamp is None:
        timestamp = hex(int(time.time()))
    
    headers = {}
    if jwt_token:
        headers["Authorization"] = f"Bearer {jwt_token}"
    
    # Use auth port with JWT
    try:
        response = requests.post(AUTH_URL, json={
            "jsonrpc": "2.0",
            "method": "engine_forkchoiceUpdatedV1",
            "params": [{
                "headBlockHash": head_hash,
                "safeBlockHash": head_hash,
                "finalizedBlockHash": head_hash
            }, {
                "timestamp": timestamp,
                "prevRandao": "0x0000000000000000000000000000000000000000000000000000000000000000",
                "suggestedFeeRecipient": "0x356981ee849c96fC40e78B0B22715345E57746fb"
            }],
            "id": 1
        }, headers=headers, timeout=2)
        return response.json()
    except Exception as e:
        return {"error": str(e)}

def main():
    print("🔷 Starting Beacon Simulator for Clique consensus")
    print(f"   RPC: {RPC_URL}")
    print(f"   Auth: {AUTH_URL}")
    print(f"   Period: {PERIOD} seconds")
    print("   This will trigger block creation automatically")
    print("   Press Ctrl+C to stop\n")
    
    # Read JWT secret
    jwt_secret = read_jwt_secret()
    if not jwt_secret:
        print("⚠️  Warning: JWT secret not found, authentication may fail")
        jwt_token = None
    else:
        jwt_token = generate_jwt_token(jwt_secret)
        print("✅ JWT token generated\n")
    
    last_block = 0
    
    while True:
        try:
            head_hash, block_num = get_head_block()
            
            if head_hash:
                # Check if we need to create a new block
                if block_num == last_block:
                    # Try to trigger block creation every period
                    result = forkchoice_updated(head_hash, jwt_token)
                    if result and 'error' in result:
                        # Only print errors if they're not authentication-related
                        if '401' not in str(result.get('error', {})):
                            pass  # Ignore other errors
                
                if block_num > last_block:
                    print(f"✅ Block {block_num} created (hash: {head_hash[:10]}...)")
                    last_block = block_num
                else:
                    # Check for pending transactions
                    try:
                        tx_status = requests.post(RPC_URL, json={
                            "jsonrpc": "2.0",
                            "method": "txpool_status",
                            "params": [],
                            "id": 1
                        }, timeout=2).json()
                        if 'result' in tx_status:
                            pending = int(tx_status['result'].get('pending', '0x0'), 16)
                            if pending > 0:
                                print(f"⏳ {pending} pending transaction(s), triggering block creation...")
                                forkchoice_updated(head_hash, jwt_token)
                    except:
                        pass
            
            time.sleep(PERIOD)
            
        except KeyboardInterrupt:
            print("\n🛑 Stopping beacon simulator...")
            break
        except Exception as e:
            print(f"Error: {e}")
            time.sleep(PERIOD)

if __name__ == "__main__":
    main()

