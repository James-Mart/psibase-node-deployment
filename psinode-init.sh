#!/bin/bash
set -ae

echo "Starting psinode initialization..."

# Set default values
SLOT=0
TOKEN_LABEL="psibase SoftHSM"
NEW_PIN=${NEW_PIN:-}

# Check if NEW_PIN is provided
if [ -z "$NEW_PIN" ]; then
  echo "ERROR: No NEW_PIN provided via environment. Please set the NEW_PIN environment variable." >&2
  exit 1
fi

# Log what we're doing (without showing the PIN values)
echo "Deleting the default token with label '$TOKEN_LABEL'..."

# Delete the default token using its known label
if softhsm2-util --delete-token --token "$TOKEN_LABEL"; then
  echo "Successfully deleted default token"
else
  echo "ERROR: Failed to delete token. The operation must be successful to continue." >&2
  exit 1
fi

# Initialize a new token
echo "Initializing new token at slot $SLOT with label '$TOKEN_LABEL'..."

# Attempt to initialize a new token
if softhsm2-util --init-token --slot $SLOT --label "$TOKEN_LABEL" --so-pin "$NEW_PIN" --pin "$NEW_PIN"; then
  echo "Successfully initialized new token"
else
  echo "ERROR: Failed to initialize new token. The operation must be successful to continue." >&2
  exit 1
fi

# Execute psinode with the original command
exec psinode "$@" 