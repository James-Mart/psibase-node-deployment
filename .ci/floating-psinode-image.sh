#!/usr/bin/env bash
set -euo pipefail

# Prints the floating psinode image reference for the upstream-drift job.
#
# ghcr.io/gofractally/psinode does not publish :latest (or any other moving
# alias). The refs that exist are version tags (v0.25.0-pre), arch-specific
# suffixes of those tags, and commit-SHA snapshots. Floating here means the
# newest multi-arch version tag: vX.Y.Z or vX.Y.Z-pre.

if [[ $# -gt 0 ]]; then
  echo "floating-psinode-image: takes no arguments" >&2
  exit 1
fi

REPO="gofractally/psinode"

token="$(
  curl -fsS "https://ghcr.io/token?service=ghcr.io&scope=repository:${REPO}:pull" \
    | jq -r '.token'
)"
if [[ -z "$token" || "$token" == "null" ]]; then
  echo "floating-psinode-image: failed to obtain an anonymous GHCR pull token" >&2
  exit 1
fi

tags_json="$(
  curl -fsS \
    -H "Authorization: Bearer ${token}" \
    "https://ghcr.io/v2/${REPO}/tags/list?n=1000"
)"

tag="$(
  python3 -c '
import json, re, sys

pat = re.compile(r"^v(\d+)\.(\d+)\.(\d+)(-pre)?$")
data = json.load(sys.stdin)
best = None
best_key = None
for tag in data.get("tags") or []:
    match = pat.match(tag)
    if not match:
        continue
    # Stable (no -pre) sorts after the matching pre-release.
    key = (
        int(match.group(1)),
        int(match.group(2)),
        int(match.group(3)),
        0 if match.group(4) else 1,
    )
    if best_key is None or key > best_key:
        best_key = key
        best = tag
if best:
    print(best)
' <<<"$tags_json"
)"

if [[ -z "$tag" ]]; then
  echo "floating-psinode-image: no version tags matching v*.*.*[-pre] on ghcr.io/${REPO}" >&2
  exit 1
fi

echo "ghcr.io/${REPO}:${tag}"
