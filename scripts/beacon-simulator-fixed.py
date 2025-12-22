#!/usr/bin/env python3
"""
Fixed Beacon Simulator for Clique consensus in post-merge mode
Properly implements Engine API calls with JWT authentication
"""

import requests
import time
import json
import os

RPC_URL = "http://localhost:8547"  # Updated to match start-prod.sh default port (avoiding Anvil on 8545)
AUTH_PORT = 8552
AUTH_URL = f"http://127.0.0.1:{AUTH_PORT}"
# Try multiple possible JWT secret paths
def find_jwt_secret():
    possible_paths = [
        os.path.expanduser("~/local-blockchain/geth/jwtsecret"),
        os.path.expanduser("~/Documents/g-group/go-ethereum-custom/scripts/start-prod/data/geth/jwtsecret"),
        "./scripts/start-prod/data/geth/jwtsecret",
        "../scripts/start-prod/data/geth/jwtsecret",
    ]
    for path in possible_paths:
        if os.path.exists(path):
            return path
    return None

JWT_SECRET_PATH = find_jwt_secret() or os.path.expanduser("~/local-blockchain/geth/jwtsecret")
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
        
        # Check response status
        if response.status_code == 401:
            return {"error": "HTTP 401: stale token"}
        if response.status_code != 200:
            return {"error": f"HTTP {response.status_code}: {response.text[:100]}"}
        
        # Check if response has content
        if not response.text or not response.text.strip():
            return {"error": "empty response from engine API"}
        
        # Try to parse JSON
        try:
            result = response.json()
        except ValueError as e:
            return {"error": f"invalid JSON response: {str(e)}, response: {response.text[:200]}"}
        
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
                    
                    if payload_resp.status_code != 200:
                        return {"error": f"getPayload HTTP {payload_resp.status_code}"}
                    
                    try:
                        payload_result = payload_resp.json()
                    except ValueError as e:
                        return {"error": f"getPayload invalid JSON: {str(e)}"}
                    
                    if 'result' in payload_result:
                        # Step 3: Execute the payload
                        new_payload = {
                            "jsonrpc": "2.0",
                            "method": "engine_newPayloadV1",
                            "params": [payload_result['result']],
                            "id": 1
                        }
                        new_payload_resp = requests.post(AUTH_URL, json=new_payload, headers=headers, timeout=5)
                        
                        if new_payload_resp.status_code != 200:
                            return {"error": f"newPayload HTTP {new_payload_resp.status_code}"}
                        
                        try:
                            new_payload_result = new_payload_resp.json()
                        except ValueError as e:
                            return {"error": f"newPayload invalid JSON: {str(e)}"}
                        
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
                                # Don't check final_result, just return success
                                return {"success": True, "blockHash": block_hash, "status": new_payload_result['result'].get('status')}
        
        return result
    except requests.exceptions.ConnectionError:
        return {"error": "connection failed"}
    except Exception as e:
        return {"error": str(e)}

def get_fresh_jwt_token(jwt_secret):
    """Generate a fresh JWT token with current timestamp"""
    if not jwt_secret:
        return None
    try:
        import jwt
        import time
        # Remove 0x prefix if present
        if jwt_secret.startswith('0x'):
            jwt_secret = jwt_secret[2:]
        
        # Try hex first (most common), then raw string
        try:
            secret_bytes = bytes.fromhex(jwt_secret)
        except ValueError:
            secret_bytes = jwt_secret.encode('utf-8')
        
        # Generate fresh token with current time
        payload = {"iat": int(time.time())}
        token = jwt.encode(payload, secret_bytes, algorithm="HS256")
        return token
    except ImportError:
        print("⚠️  PyJWT not installed. Install with: pip3 install PyJWT")
        return None
    except Exception as e:
        print(f"⚠️  Error generating JWT token: {e}")
        return None

def main():
    print("🔷 Starting Fixed Beacon Simulator for Clique consensus")
    print(f"   RPC: {RPC_URL}")
    print(f"   Auth: {AUTH_URL}")
    print(f"   Period: {PERIOD} seconds")
    print("")
    
    # Read JWT secret (we'll regenerate token periodically)
    jwt_secret = read_jwt_secret()
    if not jwt_secret:
        print("❌ Cannot read JWT secret. Exiting.")
        return
    
    # Generate initial JWT token
    jwt_token = get_fresh_jwt_token(jwt_secret)
    if not jwt_token:
        print("❌ Cannot generate JWT token. Exiting.")
        return
    
    print("✅ JWT token generated")
    print("   Waiting for node and state database to be ready...")
    
    # Wait for node to be ready and state to be accessible
    for i in range(30):
        try:
            head_hash, block_num, block_timestamp = get_head_block()
            if head_hash and block_num == 0:
                # Try to get genesis block to verify state is accessible
                response = requests.post(RPC_URL, json={
                    "jsonrpc": "2.0",
                    "method": "eth_getBlockByNumber",
                    "params": ["0x0", False],
                    "id": 1
                }, timeout=2)
                if response.status_code == 200:
                    result = response.json()
                    if 'result' in result and result['result']:
                        state_root = result['result'].get('stateRoot')
                        if state_root:
                            print("✅ Node and state database ready")
                            break
        except:
            pass
        if i < 29:
            time.sleep(1)
    else:
        print("⚠️  Node might not be fully ready, but continuing...")
    
    print("   Starting block creation loop...\n")
    
    last_block = 0
    last_timestamp = 0
    last_token_refresh = int(time.time())
    TOKEN_REFRESH_INTERVAL = 300  # Refresh token every 5 minutes
    
    while True:
        try:
            head_hash, block_num, block_timestamp = get_head_block()
            
            if head_hash:
                current_time = int(time.time())
                
                # Regenerate JWT token periodically to prevent stale token errors
                if current_time - last_token_refresh >= TOKEN_REFRESH_INTERVAL:
                    new_token = get_fresh_jwt_token(jwt_secret)
                    if new_token:
                        jwt_token = new_token
                        last_token_refresh = current_time
                        print("🔄 Refreshed JWT token (periodic refresh)")
                
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
                should_create = False
                if block_num == last_block:
                    # Same block, need to advance
                    should_create = True
                elif pending > 0:
                    # Pending transactions, create block immediately
                    should_create = True
                elif current_time >= next_timestamp:
                    # Enough time has passed
                    should_create = True
                
                if should_create:
                    result = forkchoice_updated(head_hash, jwt_token, next_timestamp)
                    if 'error' in result:
                        error_msg = str(result.get('error', ''))
                        # If authentication error or stale token, regenerate JWT token and retry
                        if '401' in error_msg or 'stale token' in error_msg.lower() or 'authentication' in error_msg.lower():
                            new_token = get_fresh_jwt_token(jwt_secret)
                            if new_token:
                                jwt_token = new_token
                                print("🔄 Regenerated JWT token (stale token detected), retrying...")
                                result = forkchoice_updated(head_hash, jwt_token, next_timestamp)
                                if 'error' in result:
                                    error_msg = str(result.get('error', ''))
                        
                        if 'error' in result:
                            if 'authentication' not in error_msg.lower() and '401' not in error_msg and 'stale' not in error_msg.lower():
                                print(f"⚠️  Block creation error: {error_msg}")
                    elif 'result' in result:
                        payload_status = result['result'].get('payloadStatus', {})
                        status = payload_status.get('status')
                        if status == 'VALID':
                            print(f"✅ Triggered block creation (block {block_num}, pending: {pending})")
                        elif status:
                            print(f"⚠️  Payload status: {status}")
                
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

