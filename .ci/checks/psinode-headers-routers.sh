#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROUTERS_YML="$REPO_ROOT/traefik/config/routers.yml"

router_middlewares() {
  local router="$1"
  awk -v router="$router" '
    $0 ~ "^    " router ":" { in_router=1; in_mw=0; next }
    in_router && /^    [^[:space:]]/ { in_router=0; in_mw=0 }
    in_router && /^      middlewares:/ { in_mw=1; next }
    in_router && in_mw && /^        - / { print $2; next }
    in_router && in_mw && /^      [^[:space:]]/ { in_mw=0 }
  ' "$ROUTERS_YML"
}

middleware_listed() {
  local router="$1"
  local middleware="$2"
  router_middlewares "$router" | grep -qx "$middleware"
}

failed=0

if middleware_listed psinode psinode-headers; then
  echo "psinode-headers must not be on the psinode router" >&2
  failed=1
fi

if ! middleware_listed x-peers-p2p psinode-headers; then
  echo "psinode-headers must be on the x-peers-p2p router" >&2
  failed=1
fi

exit "$failed"
