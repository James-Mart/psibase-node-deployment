#!/usr/bin/env bash
set -euo pipefail

# A check that cannot fail on the mutation it exists to catch is not a check.
# Inverts the first-run condition in psinode-entrypoint.sh, runs the full
# bring-up against the mutated entrypoint, and requires the failure to name the
# branch it expected, the flags it expected, and the argv it found. The
# entrypoint is restored before this script exits, on every path short of a
# SIGKILL.

if [[ $# -gt 0 ]]; then
  echo "entrypoint-mutation-check: takes no arguments" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

ENTRYPOINT="$REPO_ROOT/psinode-entrypoint.sh"

# shellcheck disable=SC2016  # the entrypoint's own source text, not an expansion
CONDITION='if [ ! -d "/root/psibase/db" ] || [ -z "$(ls -A /root/psibase/db)" ]; then'
# shellcheck disable=SC2016  # ditto
INVERTED='if ! { [ ! -d "/root/psibase/db" ] || [ -z "$(ls -A /root/psibase/db)" ]; }; then'

BACKUP=""
OUTPUT=""

restore() {
  if [[ -n "$BACKUP" && -f "$BACKUP" ]]; then
    cat "$BACKUP" >"$ENTRYPOINT"
    rm -f "$BACKUP"
    BACKUP=""
    echo "Restored psinode-entrypoint.sh."
  fi
  rm -f "$OUTPUT"
}

die() {
  echo "entrypoint-mutation-check: $*" >&2
  if [[ -n "$OUTPUT" && -f "$OUTPUT" ]]; then
    echo "--- last 40 lines of bring-up output ---" >&2
    tail -n 40 "$OUTPUT" >&2
  fi
  exit 1
}

trap restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

matches="$(grep -c -F -x -- "$CONDITION" "$ENTRYPOINT" || true)"
if [[ "$matches" != "1" ]]; then
  echo "entrypoint-mutation-check: cannot locate the first-run condition in psinode-entrypoint.sh" >&2
  echo "  want exactly one line: ${CONDITION}" >&2
  echo "  found ${matches}" >&2
  echo "  the entrypoint changed shape; update this check with it" >&2
  exit 1
fi

BACKUP="$(mktemp)"
cp "$ENTRYPOINT" "$BACKUP"

mutated="$(mktemp)"
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" == "$CONDITION" ]]; then
    printf '%s\n' "$INVERTED"
  else
    printf '%s\n' "$line"
  fi
done <"$ENTRYPOINT" >"$mutated"
cat "$mutated" >"$ENTRYPOINT"
rm -f "$mutated"

echo "Inverted the first-run condition; a fresh database now takes the resume branch."

OUTPUT="$(mktemp)"
if "$SCRIPT_DIR/bring-up.sh" >"$OUTPUT" 2>&1; then
  die "bring-up passed against an inverted entrypoint condition"
fi

require() {
  local what="$1"
  local pattern="$2"
  if ! grep -qE -- "$pattern" "$OUTPUT"; then
    die "bring-up failed, but its output never named ${what}"
  fi
}

require "the assertion that caught it" 'entrypoint branch assertion failed'
require "the expected branch and flags" \
  'expected first-run \(--pkcs11-module present, --p2p absent\)'
require "the argv it found" 'found: .*psinode.*--p2p'

echo "Bring-up caught it:"
{ grep -m1 -E 'entrypoint branch assertion failed: expected first-run' "$OUTPUT" ||
  true; } | sed 's/^/  /'

echo "entrypoint-mutation-check: ok"
