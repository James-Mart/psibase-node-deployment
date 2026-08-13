#!/usr/bin/env bash
set -euo pipefail

# Fail-closed isolation guard. Renders the compose stack described by
# COMPOSE_FILE, COMPOSE_PROJECT_NAME, and COMPOSE_ENV_FILES — the same
# environment the shipped start scripts honor — and refuses unless that
# stack is isolated from production.

if [[ $# -gt 0 ]]; then
  echo "assert-isolated: takes no arguments" >&2
  exit 1
fi

if ! command -v docker >/dev/null; then
  echo "assert-isolated: docker is required to render compose configuration" >&2
  exit 1
fi

if ! command -v python3 >/dev/null; then
  echo "assert-isolated: python3 is required to evaluate isolation" >&2
  exit 1
fi

# Same derivation as .scripts/restart-node-fresh.sh — the volume that
# script will `docker volume rm`.
COMPOSE_PROJECT="${COMPOSE_PROJECT_NAME:-$(basename "$PWD")}"
DERIVED_PSINODE_VOLUME="${COMPOSE_PROJECT}_psinode-volume"

render_out="$(mktemp)"
render_err="$(mktemp)"
trap 'rm -f "$render_out" "$render_err"' EXIT

if ! docker compose config --format json >"$render_out" 2>"$render_err"; then
  echo "assert-isolated: cannot render compose configuration" >&2
  if [[ -s "$render_err" ]]; then
    cat "$render_err" >&2
  fi
  exit 1
fi

if [[ ! -s "$render_out" ]]; then
  echo "assert-isolated: compose render is empty" >&2
  if [[ -s "$render_err" ]]; then
    cat "$render_err" >&2
  fi
  exit 1
fi

python3 - "$render_out" "$DERIVED_PSINODE_VOLUME" <<'PY'
import ipaddress
import json
import sys

EXPECTED_PROJECT = "psibase-node-ci"
FORBIDDEN_PROJECT = "psibase-node-deployment"
FORBIDDEN_VOLUME_PREFIX = "psibase-node-deployment_"
FORBIDDEN_NETWORK_NAME = "psibase_net"
FORBIDDEN_SUBNET = ipaddress.ip_network("172.30.0.0/24")
EXPECTED_PSINODE_VOLUME = f"{EXPECTED_PROJECT}_psinode-volume"

render_path, derived_psinode_volume = sys.argv[1], sys.argv[2]
objections: list[str] = []


def object_field(parent: object, key: str, label: str) -> dict | None:
    if not isinstance(parent, dict):
        objections.append(f"{label} is missing")
        return None
    value = parent.get(key)
    if not isinstance(value, dict):
        objections.append(f"{label} is missing")
        return None
    return value


def text_field(parent: object, key: str, label: str) -> str | None:
    if not isinstance(parent, dict):
        objections.append(f"{label} is missing")
        return None
    value = parent.get(key)
    if not isinstance(value, str) or value == "":
        objections.append(f"{label} is missing")
        return None
    return value


def main() -> None:
    try:
        with open(render_path, encoding="utf-8") as handle:
            data = json.load(handle)
    except json.JSONDecodeError as exc:
        objections.append(f"compose render is not JSON: {exc}")
        return
    except OSError as exc:
        objections.append(f"cannot read compose render: {exc}")
        return

    if not isinstance(data, dict):
        objections.append("compose render is not an object")
        return

    name = text_field(data, "name", "project name")
    if name is not None:
        if name == FORBIDDEN_PROJECT:
            objections.append(
                f"project name is {name!r} (production), want {EXPECTED_PROJECT!r}"
            )
        elif name != EXPECTED_PROJECT:
            objections.append(
                f"project name is {name!r}, want {EXPECTED_PROJECT!r}"
            )

    volumes = object_field(data, "volumes", "volumes")
    rendered_psinode = None
    if volumes is not None:
        if not volumes:
            objections.append("volumes are missing")
        for volume_key, volume in volumes.items():
            label = f"volume {volume_key}"
            volume_name = text_field(volume, "name", f"{label} name")
            if volume_name is None:
                continue
            if volume_name.startswith(FORBIDDEN_VOLUME_PREFIX):
                objections.append(
                    f"{label} is named {volume_name!r}, which matches {FORBIDDEN_VOLUME_PREFIX}*"
                )
            if volume_key == "psinode-volume":
                rendered_psinode = volume_name
        if "psinode-volume" not in volumes:
            objections.append("psinode-volume is missing")

    networks = object_field(data, "networks", "networks")
    if networks is not None:
        if not networks:
            objections.append("networks are missing")
        for net_key, network in networks.items():
            label = f"network {net_key}"
            net_name = text_field(network, "name", f"{label} name")
            if net_name == FORBIDDEN_NETWORK_NAME:
                objections.append(f"{label} name is {net_name!r}")

            if not isinstance(network, dict):
                objections.append(f"{label} is missing")
                continue
            ipam = network.get("ipam")
            if not isinstance(ipam, dict):
                objections.append(f"{label} ipam is missing")
                continue
            configs = ipam.get("config")
            if not isinstance(configs, list) or not configs:
                objections.append(f"{label} subnet is missing")
                continue
            for index, item in enumerate(configs):
                subnet_label = f"{label} subnet"
                if len(configs) > 1:
                    subnet_label = f"{label} subnet[{index}]"
                if not isinstance(item, dict):
                    objections.append(f"{subnet_label} is missing")
                    continue
                raw_subnet = item.get("subnet")
                if not isinstance(raw_subnet, str) or raw_subnet == "":
                    objections.append(f"{subnet_label} is missing")
                    continue
                try:
                    parsed = ipaddress.ip_network(raw_subnet, strict=False)
                except ValueError:
                    objections.append(
                        f"{subnet_label} {raw_subnet!r} is not a valid network"
                    )
                    continue
                if parsed.overlaps(FORBIDDEN_SUBNET):
                    objections.append(
                        f"{subnet_label} {raw_subnet} overlaps {FORBIDDEN_SUBNET}"
                    )

    if derived_psinode_volume != EXPECTED_PSINODE_VOLUME:
        objections.append(
            "fresh-start would destroy volume "
            f"{derived_psinode_volume!r}, which does not belong to "
            f"project {EXPECTED_PROJECT}"
        )
    elif rendered_psinode is not None and rendered_psinode != derived_psinode_volume:
        objections.append(
            "fresh-start would destroy "
            f"{derived_psinode_volume!r} but compose psinode volume is "
            f"{rendered_psinode!r}"
        )


try:
    main()
except Exception as exc:  # noqa: BLE001 — any indeterminate evaluation is a refusal
    print(
        f"assert-isolated: cannot evaluate isolation: {type(exc).__name__}: {exc}",
        file=sys.stderr,
    )
    sys.exit(1)

if not objections:
    sys.exit(0)

print("assert-isolated: refused", file=sys.stderr)
for item in objections:
    print(f"  {item}", file=sys.stderr)
sys.exit(1)
PY
