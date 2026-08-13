#!/usr/bin/env bash
set -euo pipefail

# The CI override may only isolate the stack — it may not change what is under
# test. Renders the shipped stack and the CI-overridden stack and refuses any
# difference outside the isolation deviations: project name, network name and
# subnet, static addresses, volume names, and environment values.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$REPO_ROOT"

shipped="$(mktemp)"
isolated="$(mktemp)"
trap 'rm -f "$shipped" "$isolated"' EXIT

# An outer bring-up run exports these; both renders must come from the files
# named here and nothing else.
render() {
  env -u COMPOSE_FILE -u COMPOSE_PROJECT_NAME -u COMPOSE_ENV_FILES \
    docker compose "$@" --env-file .ci/.env.ci config --format json
}

render >"$shipped"
render -f docker-compose.yml -f docker-compose.ci.yml >"$isolated"

python3 - "$shipped" "$isolated" <<'PY'
import difflib
import json
import sys

shipped_path, isolated_path = sys.argv[1], sys.argv[2]


def strip_allowed(config: dict) -> dict:
    """Remove the axes the isolation override is allowed to change."""
    config.pop("name", None)

    for service in config.get("services", {}).values():
        if not isinstance(service, dict):
            continue
        service.pop("environment", None)
        for attachment in service.get("networks", {}).values():
            if isinstance(attachment, dict):
                attachment.pop("ipv4_address", None)

    for network in config.get("networks", {}).values():
        if isinstance(network, dict):
            network.pop("name", None)
            network.pop("ipam", None)

    for volume in config.get("volumes", {}).values():
        if isinstance(volume, dict):
            volume.pop("name", None)

    return config


def canonical(path: str) -> list[str]:
    with open(path, encoding="utf-8") as handle:
        config = strip_allowed(json.load(handle))
    return json.dumps(config, indent=2, sort_keys=True).splitlines()


leak = list(
    difflib.unified_diff(
        canonical(shipped_path),
        canonical(isolated_path),
        fromfile="shipped stack",
        tofile="CI stack",
        lineterm="",
    )
)

if leak:
    print(
        "compose-ci-fidelity: the CI override changes the stack under test",
        file=sys.stderr,
    )
    print(
        "  allowed: project name, network name and subnet, static addresses, "
        "volume names, environment values",
        file=sys.stderr,
    )
    for line in leak:
        print(f"  {line}", file=sys.stderr)
    sys.exit(1)
PY
