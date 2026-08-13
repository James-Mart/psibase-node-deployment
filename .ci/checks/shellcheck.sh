#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Pinned digest — do not use the floating :stable tag (gates every PR).
SHELLCHECK_IMAGE='koalaman/shellcheck@sha256:bb596a0d169b85ddd81d8b6d3a2ff6d5baf5fca10b97f575ebc647c3dff62b3d'

mapfile -t scripts < <(git -C "$REPO_ROOT" ls-files -- '*.sh')

if [[ ${#scripts[@]} -eq 0 ]]; then
  echo "No tracked shell scripts found"
  exit 0
fi

docker run --rm \
  -v "$REPO_ROOT:/mnt:ro" \
  -w /mnt \
  "$SHELLCHECK_IMAGE" \
  "${scripts[@]}"
