#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Variables injected by the runtime rather than by the operator. They may
# appear as ${VAR} in compose files without belonging in .env.template.
IGNORE=(
  # Compose sets the project name from the directory, or from an exported
  # COMPOSE_PROJECT_NAME (CI isolation does this). Not operator .env config.
  COMPOSE_PROJECT_NAME
  # Process working directory at compose invocation. Always present on the
  # host; operators do not declare it.
  PWD
)

cd "$REPO_ROOT"
shopt -s nullglob

is_ignored() {
  local candidate="$1"
  local ignored
  for ignored in "${IGNORE[@]}"; do
    if [[ "$candidate" == "$ignored" ]]; then
      return 0
    fi
  done
  return 1
}

# Unique names, dropping ignored and empty lines.
normalize() {
  local name
  sort -u | while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    is_ignored "$name" && continue
    printf '%s\n' "$name"
  done
}

# ${VAR} and ${VAR:-default} across docker-compose*.yml.
compose_refs() {
  local file
  for file in docker-compose*.yml; do
    grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*(:-[^}]*)?\}' "$file" \
      | sed -E 's/^\$\{([A-Za-z_][A-Za-z0-9_]*).*/\1/' || true
  done
}

# {{ env "VAR" }} across traefik/.
traefik_refs() {
  grep -rhoE --include='*.yml' \
    '\{\{[[:space:]]*env[[:space:]]+"[A-Za-z_][A-Za-z0-9_]*"[[:space:]]*\}\}' \
    traefik \
    | grep -oE '"[A-Za-z_][A-Za-z0-9_]*"' \
    | tr -d '"' || true
}

# Declarations in .env.template, including commented-out optional values.
declared_vars() {
  grep -E '^[[:space:]]*#?[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' .env.template \
    | sed -E 's/^[[:space:]]*#?[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=.*/\1/' || true
}

ref_file="$(mktemp)"
decl_file="$(mktemp)"
trap 'rm -f "$ref_file" "$decl_file"' EXIT

{ compose_refs; traefik_refs; } | normalize >"$ref_file"
declared_vars | normalize >"$decl_file"

missing="$(comm -23 "$ref_file" "$decl_file")"
unused="$(comm -13 "$ref_file" "$decl_file")"

failed=0

print_indented() {
  local line
  while IFS= read -r line; do
    printf '  %s\n' "$line" >&2
  done <<< "$1"
}

if [[ -n "$missing" ]]; then
  echo "Referenced but not declared in .env.template:" >&2
  print_indented "$missing"
  failed=1
fi

if [[ -n "$unused" ]]; then
  echo "Declared in .env.template but never referenced:" >&2
  print_indented "$unused"
  failed=1
fi

exit "$failed"
