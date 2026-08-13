#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.ci/lib/entrypoint-branch-assert.sh
source "$SCRIPT_DIR/../lib/entrypoint-branch-assert.sh"

assert_ok() {
  local branch="$1"
  local argv="$2"
  if ! assert_psinode_argv_branch "$branch" "$argv"; then
    echo "expected pass for branch=${branch} argv=${argv}" >&2
    return 1
  fi
}

assert_fail() {
  local branch="$1"
  local argv="$2"
  if assert_psinode_argv_branch "$branch" "$argv"; then
    echo "expected fail for branch=${branch} argv=${argv}" >&2
    return 1
  fi
}

first_run_argv='psinode db -p ci-producer -o ci.example.test -l 8090 --database-cache-size=1g --pkcs11-module=/softhsm-lib/libsofthsm2.so'
resume_argv='psinode db -p ci-producer -o ci.example.test --p2p -l 8090 --database-cache-size=1g'

assert_ok first-run "$first_run_argv"
assert_ok resume "$resume_argv"
assert_fail first-run "$resume_argv"
assert_fail resume "$first_run_argv"
assert_fail first-run 'psinode db -p ci-producer -o ci.example.test -l 8090 --database-cache-size=1g'
assert_fail resume 'psinode db -p ci-producer -o ci.example.test -l 8090 --database-cache-size=1g --pkcs11-module=/softhsm-lib/libsofthsm2.so'

echo "entrypoint branch assert stubs ok"
