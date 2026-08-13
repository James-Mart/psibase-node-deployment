#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKS_DIR="$SCRIPT_DIR/checks"

run_check() {
  local name="$1"
  local check_script="$CHECKS_DIR/${name}.sh"

  if [[ ! -f "$check_script" ]]; then
    echo "FAIL $name (missing check script: $check_script)" >&2
    return 1
  fi

  if "$check_script"; then
    echo "PASS $name"
    return 0
  fi

  echo "FAIL $name"
  return 1
}

if [[ $# -eq 1 ]]; then
  run_check "$1"
  exit $?
fi

if ! compgen -G "$CHECKS_DIR"/*.sh > /dev/null; then
  echo "No checks found in $CHECKS_DIR" >&2
  exit 1
fi

failed=0
while IFS= read -r -d '' check_script; do
  name="$(basename "$check_script" .sh)"
  if ! run_check "$name"; then
    failed=1
  fi
done < <(find "$CHECKS_DIR" -maxdepth 1 -name '*.sh' -print0 | sort -z)

exit "$failed"
