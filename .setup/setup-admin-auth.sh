#!/bin/bash
# setup-admin-auth.sh

set -euo pipefail

USERNAME=""
PASSWORD_STDIN=false

usage() {
  echo "Usage: $0 <username>"
  echo "       $0 --username <name> --password-stdin"
  echo "Example: $0 psinode-admin"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --username)
      [[ $# -ge 2 ]] || usage
      USERNAME="$2"
      shift 2
      ;;
    --password-stdin)
      PASSWORD_STDIN=true
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      ;;
    *)
      if [[ -n "$USERNAME" ]]; then
        echo "Error: username specified more than once." >&2
        usage
      fi
      USERNAME="$1"
      shift
      ;;
  esac
done

if [[ "$PASSWORD_STDIN" == true && -z "$USERNAME" ]]; then
  echo "Error: --password-stdin requires --username." >&2
  usage
fi

if [[ -z "$USERNAME" ]]; then
  usage
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$REPO_ROOT/.env" ]; then
  AUTHELIA_IMAGE=$(grep -E '^AUTHELIA_IMAGE=' "$REPO_ROOT/.env" | head -1 | cut -d= -f2-) || AUTHELIA_IMAGE=""
fi

if [ -z "${AUTHELIA_IMAGE:-}" ]; then
  echo "Error: AUTHELIA_IMAGE is not set. Add it to .env (see .env.template)." >&2
  exit 1
fi

mkdir -p "$REPO_ROOT/traefik/auth" "$REPO_ROOT/authelia"

echo "Creating credentials for user: $USERNAME"

if [[ "$PASSWORD_STDIN" == true ]]; then
  read -r PASSWORD
else
  read -s -r -p "Enter password: " PASSWORD
  echo
  read -s -r -p "Confirm password: " PASSWORD_CONFIRM
  echo

  if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
    echo "Error: passwords do not match." >&2
    exit 1
  fi
fi

HASH=$(docker run --rm "$AUTHELIA_IMAGE" authelia crypto hash generate argon2 --password "$PASSWORD")
HASH=${HASH#Digest: }

if [[ "$HASH" != \$argon2id\$* ]]; then
  echo "Error: failed to generate Authelia password hash. Check AUTHELIA_IMAGE and Docker." >&2
  exit 1
fi

cd "$REPO_ROOT"

docker run --rm httpd:2.4-alpine htpasswd -nbB "$USERNAME" "$PASSWORD" > ./traefik/auth/users

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
