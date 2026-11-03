#!/usr/bin/env bash
set -euo pipefail

# Download a psinode image artifact from a gofractally/image-builders run,
# load it into the local Docker store, and print the PSINODE_IMAGE value
# and the artifact digest.
#
# The Digest column on the Actions run is the SHA-256 of the uploaded zip,
# not the Docker image id. This script hashes that zip and prints the same
# value. Those runs upload `docker save` archives (psinode-amd64-image /
# psinode-arm64-image). They do not push a GHCR tag.

repo="gofractally/image-builders"

usage() {
  echo "usage: $(basename "$0") <image-builders-run-id>" >&2
  exit 1
}

if [[ $# -ne 1 ]]; then
  usage
fi

run_id="$1"
if [[ ! "$run_id" =~ ^[0-9]+$ ]]; then
  echo "run id must be numeric: ${run_id}" >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64)
    arch="amd64"
    ;;
  aarch64 | arm64)
    arch="arm64"
    ;;
  *)
    echo "unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

if ! command -v gh >/dev/null 2>&1; then
  echo "gh is required (https://cli.github.com)" >&2
  exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi

artifact="psinode-${arch}-image"
archive="${artifact}.tar"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

mapfile -t rows < <(
  gh api "repos/${repo}/actions/runs/${run_id}/artifacts" \
    --jq ".artifacts[] | select(.name==\"${artifact}\") | [.id, .digest] | @tsv"
)
if [[ ${#rows[@]} -ne 1 ]]; then
  echo "expected one ${artifact} artifact on run ${run_id}, found ${#rows[@]}" >&2
  exit 1
fi

IFS=$'\t' read -r artifact_id recorded_digest <<<"${rows[0]}"
if [[ -z "$artifact_id" ]]; then
  echo "artifact ${artifact} has no id" >&2
  exit 1
fi

echo "downloading ${artifact} from run ${run_id}" >&2
gh api \
  -H "Accept: application/vnd.github+json" \
  "repos/${repo}/actions/artifacts/${artifact_id}/zip" \
  >"${workdir}/artifact.zip"

digest="sha256:$(sha256sum "${workdir}/artifact.zip" | awk '{print $1}')"
if [[ -n "$recorded_digest" && "$recorded_digest" != "null" && "$digest" != "$recorded_digest" ]]; then
  echo "downloaded zip digest ${digest} does not match GitHub ${recorded_digest}" >&2
  exit 1
fi

python3 -c '
import sys, zipfile
from pathlib import Path
dest, archive = sys.argv[1:]
with zipfile.ZipFile(archive) as zf:
    zf.extractall(dest)
' "$workdir" "${workdir}/artifact.zip"

if [[ ! -f "${workdir}/${archive}" ]]; then
  echo "expected ${archive} in the artifact download" >&2
  exit 1
fi

echo "loading ${archive}" >&2
load_output="$(docker load -i "${workdir}/${archive}")"
printf '%s\n' "$load_output" >&2

image=""
while IFS= read -r line; do
  if [[ "$line" == "Loaded image: "* ]]; then
    image="${line#"Loaded image: "}"
  fi
done <<<"$load_output"

if [[ -z "$image" ]]; then
  echo "docker load did not report an image name" >&2
  exit 1
fi

echo "PSINODE_IMAGE=${image}"
echo "${digest}"
