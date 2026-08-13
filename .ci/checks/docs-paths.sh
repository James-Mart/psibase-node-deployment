#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

looks_like_repo_path() {
  local token="$1"

  [[ "$token" == *'/'* ]] || return 1
  [[ "$token" == *' '* ]] && return 1
  [[ "$token" == *'://'* ]] && return 1

  case "$token" in
    ./*|.scripts/*|.setup/*|traefik/*|authelia/*|softhsm/*|ddclient/*|.ci/*)
      return 0
      ;;
  esac

  [[ "$token" =~ \.[A-Za-z0-9]+$ ]]
}

normalize_path() {
  local token="$1"

  token="${token%/}"
  token="${token#./}"
  printf '%s' "$token"
}

path_exists() {
  local candidate="$1"

  [[ -e "$REPO_ROOT/$candidate" || -e "$REPO_ROOT/${candidate%/}" ]]
}

failed=0

while IFS= read -r -d '' md_file; do
  rel_md="${md_file#"$REPO_ROOT"/}"
  line_no=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))

    rest="$line"
    while [[ "$rest" =~ \`([^\`]+)\` ]]; do
      token="${BASH_REMATCH[1]}"
      rest="${rest#*\`"${BASH_REMATCH[1]}"\`}"

      [[ "$token" == *'#'* ]] && token="${token%%#*}"

      if ! looks_like_repo_path "$token"; then
        continue
      fi

      candidate="$(normalize_path "$token")"
      if path_exists "$candidate"; then
        continue
      fi

      printf '%s:%s: missing path %s\n' "$rel_md" "$line_no" "$token" >&2
      failed=1
    done
  done <"$md_file"
done < <(find "$REPO_ROOT" -name '*.md' -print0)

exit "$failed"
