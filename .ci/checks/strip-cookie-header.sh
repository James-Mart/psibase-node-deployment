#!/usr/bin/env bash
set -euo pipefail

# Public psinode must drop only authelia_session. It must not blank Cookie.
# Authelia-gated and x-* routers must not run the filter.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

MIDDLEWARES="$REPO_ROOT/traefik/config/middlewares.yml"
ROUTERS="$REPO_ROOT/traefik/config/routers.yml"
TRAEFIK="$REPO_ROOT/traefik/traefik.yml"
COMPOSE="$REPO_ROOT/docker-compose.proxy.yml"
PLUGIN_DIR="$REPO_ROOT/traefik/plugins-local/src/github.com/psibase/strip-authelia-session"

COOKIE_MIDDLEWARE='strip-authelia-session'
PLUGIN_NAME='stripAutheliaSession'
MODULE_NAME='github.com/psibase/strip-authelia-session'
COOKIE_NAME='authelia_session'
PUBLIC_ROUTER='psinode'
FORBIDDEN_ROUTERS=(
  x-peers-p2p
  x-services
  dashboard
  logs
  disk
  auth
)

python3 - \
  "$MIDDLEWARES" \
  "$ROUTERS" \
  "$TRAEFIK" \
  "$COMPOSE" \
  "$PLUGIN_DIR" \
  "$COOKIE_MIDDLEWARE" \
  "$PLUGIN_NAME" \
  "$MODULE_NAME" \
  "$COOKIE_NAME" \
  "$PUBLIC_ROUTER" \
  "${FORBIDDEN_ROUTERS[@]}" <<'PY'
import re
import sys
from pathlib import Path

middlewares_path = Path(sys.argv[1])
routers_path = Path(sys.argv[2])
traefik_path = Path(sys.argv[3])
compose_path = Path(sys.argv[4])
plugin_dir = Path(sys.argv[5])
cookie_middleware = sys.argv[6]
plugin_name = sys.argv[7]
module_name = sys.argv[8]
cookie_name = sys.argv[9]
public_router = sys.argv[10]
forbidden_routers = sys.argv[11:]

middlewares_text = middlewares_path.read_text(encoding="utf-8")
routers_text = routers_path.read_text(encoding="utf-8")
traefik_text = traefik_path.read_text(encoding="utf-8")
compose_text = compose_path.read_text(encoding="utf-8")

BLANK_COOKIE = re.compile(r"""Cookie:\s*(?:""|'')""")


def fail(message: str) -> None:
    print(f"strip-cookie-header: {message}", file=sys.stderr)
    sys.exit(1)


def block_for(text: str, key: str, indent: str) -> str | None:
    parent = indent[:-2]
    match = re.search(
        rf"(?m)^{indent}{re.escape(key)}:\n(.*?)(?=^{indent}\S|^{parent}\S|\Z)",
        text,
        re.DOTALL,
    )
    if not match:
        return None
    return match.group(1)


def router_middlewares(text: str, router: str) -> list[str]:
    block = block_for(text, router, "    ")
    if block is None:
        raise KeyError(router)
    listed = re.search(
        r"(?m)^      middlewares:\n(.*?)(?=^      \S|\Z)",
        block,
        re.DOTALL,
    )
    if listed is None:
        return []
    return re.findall(r"(?m)^        - (.+)\s*$", listed.group(1))


def middleware_block(name: str) -> str:
    block = block_for(middlewares_text, name, "    ")
    if block is None:
        fail(f"missing middleware {name!r} in {middlewares_path}")
    return block


def is_session_filter(block: str) -> bool:
    return (
        plugin_name in block
        or re.search(rf"(?m)^          cookieName:\s*{re.escape(cookie_name)}\s*$", block) is not None
    )


filter_block = middleware_block(cookie_middleware)

if BLANK_COOKIE.search(filter_block):
    fail(
        f"{cookie_middleware!r} blanks the Cookie header; "
        f"it must remove only {cookie_name!r}"
    )

if not re.search(
    rf"(?m)^      plugin:\n        {re.escape(plugin_name)}:\n          cookieName:\s*{re.escape(cookie_name)}\s*$",
    filter_block,
):
    fail(
        f"public filter {cookie_middleware!r} must pin cookieName {cookie_name!r} "
        f"on the local plugin {plugin_name!r}"
    )

try:
    public_chain = router_middlewares(routers_text, public_router)
except KeyError:
    fail(f"missing public router {public_router!r} in {routers_path}")

if cookie_middleware not in public_chain:
    fail(
        f"public router {public_router!r} does not strip {cookie_name!r}; "
        f"found {public_chain!r}"
    )

for name in public_chain:
    block = middleware_block(name)
    if BLANK_COOKIE.search(block):
        fail(
            f"public router {public_router!r} middleware {name!r} blanks the Cookie header"
        )

for router in forbidden_routers:
    try:
        chain = router_middlewares(routers_text, router)
    except KeyError:
        fail(f"missing router {router!r} in {routers_path}")
    for name in chain:
        if name == cookie_middleware or is_session_filter(middleware_block(name)):
            fail(
                f"router {router!r} must not run the {cookie_name!r} filter; "
                f"found {chain!r}"
            )

local_plugin = re.search(
    rf"(?m)^    {re.escape(plugin_name)}:\n      moduleName:\s*(\S+)\s*$",
    traefik_text,
)
if local_plugin is None or local_plugin.group(1) != module_name:
    fail(
        f"{traefik_path} must declare localPlugins.{plugin_name} "
        f"moduleName {module_name!r}"
    )

if not re.search(r"(?m)^experimental:\n(?:[ \t].*\n)*?  localPlugins:\n", traefik_text):
    fail(f"{plugin_name!r} must be declared under experimental.localPlugins")

remote = re.search(r"(?m)^  plugins:\n(.*?)(?=^[^\s]|\Z)", traefik_text, re.DOTALL)
if remote and (
    re.search(rf"(?m)^    {re.escape(plugin_name)}:\s*$", remote.group(1))
    or module_name in remote.group(1)
):
    fail(
        f"{plugin_name!r} must not be a remote plugin under experimental.plugins; "
        "Traefik would download it at startup"
    )

required = [
    plugin_dir / ".traefik.yml",
    plugin_dir / "plugin.go",
    plugin_dir / "go.mod",
]
for path in required:
    if not path.is_file():
        fail(f"missing in-repo plugin file {path}")

manifest = (plugin_dir / ".traefik.yml").read_text(encoding="utf-8")
if f"import: {module_name}" not in manifest:
    fail(f"plugin manifest import must be {module_name!r}")

plugin_source = (plugin_dir / "plugin.go").read_text(encoding="utf-8")
if 'Set("Cookie", "")' in plugin_source or "Cookie: \"\"" in plugin_source:
    fail("plugin source must not set the Cookie header to an empty string")

if not re.search(
    r"(?m)^\s*-\s*[\"']?\./traefik/plugins-local:/plugins-local(?::ro)?[\"']?\s*$",
    compose_text,
):
    fail(
        f"{compose_path} must mount ./traefik/plugins-local at /plugins-local "
        "so Traefik loads the local plugin"
    )

if not re.search(r"(?m)^    working_dir:\s*/\s*$", compose_text):
    fail(
        f"{compose_path} must set reverse-proxy working_dir to / "
        "so ./plugins-local resolves to the mounted plugin"
    )
PY

echo "strip-cookie-header check ok"
