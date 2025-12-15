#!/bin/bash
# Import validator account for Clique consensus

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

DATADIR="${HOME}/local-blockchain"
VALIDATOR_PRIVATE_KEY="9de1394869030ea18ee8930c533722d71f6990b5576dee849b9c23b7d094c186"
PASSWORD="test1"

# Create temp key file
TEMP_KEYFILE=$(mktemp)
echo "$VALIDATOR_PRIVATE_KEY" > "$TEMP_KEYFILE"

# Create password file
TEMP_PASSWORD=$(mktemp)
echo "$PASSWORD" > "$TEMP_PASSWORD"

# Import the account
echo "Importing validator account..."
./build/bin/geth account import \
  --datadir "$DATADIR" \
  --password "$TEMP_PASSWORD" \
  "$TEMP_KEYFILE" 2>&1 | grep -E "Address|imported" || echo "Account imported or already exists"

# Cleanup
rm -f "$TEMP_KEYFILE" "$TEMP_PASSWORD"

echo "✅ Validator account ready"

