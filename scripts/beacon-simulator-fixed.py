#!/usr/bin/env python3
"""
Fixed Beacon Simulator for Clique consensus in post-merge mode
Properly implements Engine API calls with JWT authentication
"""

import requests
import time
import json
import os

RPC_URL = "http://localhost:8546"
AUTH_PORT = 8551
AUTH_URL = f"http://127.0.0.1:{AUTH_PORT}"
JWT_SECRET_PATH = os.path.expanduser("~/local-blockchain/geth/jwtsecret")
PERIOD = 5  # Clique period in seconds

def read_jwt_secret():
    """Read JWT secret from file"""
    try:
        with open(JWT_SECRET_PATH, 'rb') as f:
            content = f.read().strip()
            # Decode as UTF-8, handling errors
            secret_str = content.decode('utf-8', errors='ignore').strip()
            # Remove 0x prefix if present
            if secret_str.startswith('0x'):
                secret_str = secret_str[2:]
            return secret_str
    except FileNotFoundError:
        print(f"❌ JWT secret not found at {JWT_SECRET_PATH}")
        return None

def generate_jwt_token(secret_str):
    """Generate JWT token for Engine API authentication"""
    try:
        import jwt
        # Remove 0x prefix if present
        if secret_str.startswith('0x'):
            secret_str = secret_str[2:]
        
        # Try hex first (most common), then raw string
        try:
            secret_bytes = bytes.fromhex(secret_str)
        except ValueError:
            secret_bytes = secret_str.encode('utf-8')
        
        payload = {"iat": int(time.time())}
        token = jwt.encode(payload, secret_bytes, algorithm="HS256")
        return token
    except ImportError:
        print("⚠️  PyJWT not installed. Install with: pip3 install PyJWT")
        return None

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
            return result['result']['hash'], int(result['result']['number'], 16), int(result['result']['timestamp'], 16)
        return None, 0, 0
    except Exception as e:
        return None, 0, 0

def forkchoice_updated(head_hash, jwt_token, timestamp):
    """Call ForkchoiceUpdated to trigger block creation - full flow"""
    headers = {"Content-Type": "application/json"}
    if jwt_token:
        headers["Authorization"] = f"Bearer {jwt_token}"
    
    # Step 1: ForkchoiceUpdated with payload attributes
    payload = {
        "jsonrpc": "2.0",
        "method": "engine_forkchoiceUpdatedV1",
        "params": [{
            "headBlockHash": head_hash,
            "safeBlockHash": head_hash,
            "finalizedBlockHash": head_hash
        }, {
            "timestamp": hex(timestamp),
            "prevRandao": "0x0000000000000000000000000000000000000000000000000000000000000000",
            "suggestedFeeRecipient": "0x356981ee849c96fC40e78B0B22715345E57746fb"
        }],
        "id": 1
    }
    
    try:
        response = requests.post(AUTH_URL, json=payload, headers=headers, timeout=5)
        result = response.json()
        
        if 'error' in result:
            if '401' in str(result.get('error', {})):
                return {"error": "authentication failed"}
            return result
        
        # Step 2: If we got a payload ID, get the payload
        if 'result' in result:
            payload_status = result['result'].get('payloadStatus', {})
            if payload_status.get('status') in ['VALID', 'SYNCING']:
                payload_id = result['result'].get('payloadId')
                if payload_id:
                    # Get the payload
                    get_payload = {
                        "jsonrpc": "2.0",
                        "method": "engine_getPayloadV1",
                        "params": [payload_id],
                        "id": 1
                    }
                    payload_resp = requests.post(AUTH_URL, json=get_payload, headers=headers, timeout=5)
                    payload_result = payload_resp.json()
                    
                    if 'result' in payload_result:
                        # Step 3: Execute the payload
                        new_payload = {
                            "jsonrpc": "2.0",
                            "method": "engine_newPayloadV1",
                            "params": [payload_result['result']],
                            "id": 1
                        }
                        new_payload_resp = requests.post(AUTH_URL, json=new_payload, headers=headers, timeout=5)
                        new_payload_result = new_payload_resp.json()
                        
                        # Step 4: Update forkchoice with new head (even if status is SYNCING)
                        if 'result' in new_payload_result:
                            block_hash = payload_result['result'].get('blockHash')
                            if block_hash:
                                # Wait a bit for block to be processed
                                time.sleep(0.5)
                                
                                final_fc = {
                                    "jsonrpc": "2.0",
                                    "method": "engine_forkchoiceUpdatedV1",
                                    "params": [{
                                        "headBlockHash": block_hash,
                                        "safeBlockHash": block_hash,
                                        "finalizedBlockHash": head_hash  # Keep old finalized
                                    }, None],
                                    "id": 1
                                }
                                final_result = requests.post(AUTH_URL, json=final_fc, headers=headers, timeout=5)
                                return {"success": True, "blockHash": block_hash, "status": new_payload_result['result'].get('status')}
        
        return result
    except requests.exceptions.ConnectionError:
        return {"error": "connection failed"}
    except Exception as e:
        return {"error": str(e)}

def main():
    print("🔷 Starting Fixed Beacon Simulator for Clique consensus")
    print(f"   RPC: {RPC_URL}")
    print(f"   Auth: {AUTH_URL}")
    print(f"   Period: {PERIOD} seconds")
    print("")
    
    # Read and generate JWT token
    jwt_secret = read_jwt_secret()
    if not jwt_secret:
        print("❌ Cannot read JWT secret. Exiting.")
        return
    
    jwt_token = generate_jwt_token(jwt_secret)
    if not jwt_token:
        print("❌ Cannot generate JWT token. Exiting.")
        return
    
    print("✅ JWT token generated")
    print("   Starting block creation loop...\n")
    
    last_block = 0
    last_timestamp = 0
    
    while True:
        try:
            head_hash, block_num, block_timestamp = get_head_block()
            
            if head_hash:
                current_time = int(time.time())
                # Calculate next timestamp (parent time + period, or current time if later)
                next_timestamp = max(block_timestamp + PERIOD, current_time)
                
                # Check for pending transactions
                try:
                    tx_status = requests.post(RPC_URL, json={
                        "jsonrpc": "2.0",
                        "method": "txpool_status",
                        "params": [],
                        "id": 1
                    }, timeout=2).json()
                    pending = int(tx_status.get('result', {}).get('pending', '0x0'), 16) if 'result' in tx_status else 0
                except:
                    pending = 0
                
                # Create block if:
                # 1. We're still on the same block (need to advance)
                # 2. There are pending transactions
                # 3. Enough time has passed (Clique period)
                if block_num == last_block or pending > 0:
                    if current_time >= next_timestamp or pending > 0:
                        result = forkchoice_updated(head_hash, jwt_token, next_timestamp)
                        if 'error' not in result:
                            if 'result' in result and result['result'].get('payloadStatus', {}).get('status') == 'VALID':
                                print(f"✅ Triggered block creation (block {block_num}, pending: {pending})")
                            # Even if we get an error, it might be expected
                        elif 'authentication' not in str(result.get('error', '')).lower():
                            # Only print non-auth errors
                            pass
                
                if block_num > last_block:
                    print(f"✅ Block {block_num} created! (hash: {head_hash[:10]}...)")
                    last_block = block_num
                    last_timestamp = block_timestamp
            
            time.sleep(1)  # Check every second
            
        except KeyboardInterrupt:
            print("\n🛑 Stopping beacon simulator...")
            break
        except Exception as e:
            print(f"Error: {e}")
            time.sleep(PERIOD)

if __name__ == "__main__":
    main()

