#!/usr/bin/env bash
set -euo pipefail

# Public psinode must blank Cookie; Authelia-gated and x-* routers must not.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

MIDDLEWARES="$REPO_ROOT/traefik/config/middlewares.yml"
ROUTERS="$REPO_ROOT/traefik/config/routers.yml"

COOKIE_MIDDLEWARE='strip-cookie-header'
PUBLIC_ROUTER='psinode'
FORBIDDEN_ROUTERS=(
  x-peers-p2p
  x-services
  dashboard
  logs
  disk
  auth
)

python3 - "$MIDDLEWARES" "$ROUTERS" "$COOKIE_MIDDLEWARE" "$PUBLIC_ROUTER" "${FORBIDDEN_ROUTERS[@]}" <<'PY'
import re
import sys
from pathlib import Path

middlewares_path = Path(sys.argv[1])
routers_path = Path(sys.argv[2])
cookie_middleware = sys.argv[3]
public_router = sys.argv[4]
forbidden_routers = sys.argv[5:]

middlewares_text = middlewares_path.read_text(encoding="utf-8")
routers_text = routers_path.read_text(encoding="utf-8")

middleware_block = re.search(
    rf"(?m)^    {re.escape(cookie_middleware)}:\n(.*?)(?=^    \w|\Z)",
    middlewares_text,
    re.DOTALL,
)
if not middleware_block:
    print(
        f"strip-cookie-header: missing middleware {cookie_middleware!r} in {middlewares_path}",
        file=sys.stderr,
    )
    sys.exit(1)

if not re.search(r'(?m)^          Cookie: ""\s*$', middleware_block.group(1)):
    print(
        f"strip-cookie-header: {cookie_middleware!r} must set Cookie to an empty string",
        file=sys.stderr,
    )
    sys.exit(1)


def router_middlewares(text: str, router: str) -> list[str]:
    block = re.search(
        rf"(?m)^    {re.escape(router)}:\n(.*?)(?=^    \w|\Z)",
        text,
        re.DOTALL,
    )
    if not block:
        raise KeyError(router)
    return re.findall(r"(?m)^        - (.+)\s*$", block.group(1))


def fail(message: str) -> None:
    print(f"strip-cookie-header: {message}", file=sys.stderr)
    sys.exit(1)

try:
    public_chain = router_middlewares(routers_text, public_router)
except KeyError:
    fail(f"missing public router {public_router!r} in {routers_path}")

if cookie_middleware not in public_chain:
    fail(
        f"public router {public_router!r} must include {cookie_middleware!r}; "
        f"found {public_chain!r}"
    )

for router in forbidden_routers:
    try:
        chain = router_middlewares(routers_text, router)
    except KeyError:
        fail(f"missing router {router!r} in {routers_path}")
    if cookie_middleware in chain:
        fail(
            f"router {router!r} must not include {cookie_middleware!r}; "
            f"found {chain!r}"
        )
PY

echo "strip-cookie-header check ok"
