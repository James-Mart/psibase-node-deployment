#!/bin/bash
# setup-admin-auth.sh

set -euo pipefail

# Check if username was provided
if [ $# -ne 1 ]; then
  echo "Usage: $0 <username>"
  echo "Example: $0 psinode-admin"
  exit 1
fi

USERNAME=$1
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$REPO_ROOT/.env" ]; then
  AUTHELIA_IMAGE=$(grep -E '^AUTHELIA_IMAGE=' "$REPO_ROOT/.env" | head -1 | cut -d= -f2-) || AUTHELIA_IMAGE=""
fi

if [ -z "${AUTHELIA_IMAGE:-}" ]; then
  echo "Error: AUTHELIA_IMAGE is not set. Add it to .env (see .env.template)." >&2
  exit 1
fi

# Create directories for authentication files
mkdir -p "$REPO_ROOT/traefik/auth" "$REPO_ROOT/authelia"

# Install apache2-utils for htpasswd utility
sudo apt-get update && sudo apt-get install -y apache2-utils

echo "Creating credentials for user: $USERNAME"
read -s -r -p "Enter password: " PASSWORD
echo
read -s -r -p "Confirm password: " PASSWORD_CONFIRM
echo

if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
  echo "Error: passwords do not match." >&2
  exit 1
fi

HASH=$(docker run --rm "$AUTHELIA_IMAGE" authelia crypto hash generate argon2 --password "$PASSWORD")
HASH=${HASH#Digest: }

if [[ ! "$HASH" == '$argon2id$'* ]]; then
  echo "Error: failed to generate Authelia password hash. Check AUTHELIA_IMAGE and Docker." >&2
  exit 1
fi

cd "$REPO_ROOT"

htpasswd -bc ./traefik/auth/users "$USERNAME" "$PASSWORD"

{
  echo "users:"
  echo "  ${USERNAME}:"
  echo "    disabled: false"
  echo "    displayname: ${USERNAME}"
  printf '    password: %s\n' "$HASH"
} > ./authelia/users_database.yml

chmod 600 ./traefik/auth/users ./authelia/users_database.yml

echo "Admin authentication credentials provisioned for $USERNAME"
echo "Restart Docker Compose to apply changes: docker compose down && docker compose up -d"
