#!/usr/bin/env bash

# Pure argv assertions for psinode-entrypoint.sh branches (first-run vs resume).
# Sourced by bring-up.sh and by the stub check in .ci/checks/.

assert_psinode_argv_branch() {
  local branch="$1"
  local argv="$2"

  case "$branch" in
    first-run)
      local want="--pkcs11-module present, --p2p absent"
      if [[ "$argv" != *"--pkcs11-module"* ]]; then
        echo "entrypoint branch assertion failed: expected first-run (${want}); argv missing --pkcs11-module; found: ${argv}" >&2
        return 1
      fi
      if [[ "$argv" == *"--p2p"* ]]; then
        echo "entrypoint branch assertion failed: expected first-run (${want}); argv has --p2p; found: ${argv}" >&2
        return 1
      fi
      ;;
    resume)
      local want="--p2p present, --pkcs11-module absent"
      if [[ "$argv" != *"--p2p"* ]]; then
        echo "entrypoint branch assertion failed: expected resume (${want}); argv missing --p2p; found: ${argv}" >&2
        return 1
      fi
      if [[ "$argv" == *"--pkcs11-module"* ]]; then
        echo "entrypoint branch assertion failed: expected resume (${want}); argv has --pkcs11-module; found: ${argv}" >&2
        return 1
      fi
      ;;
    *)
      echo "entrypoint branch assertion failed: unknown branch ${branch}" >&2
      return 1
      ;;
  esac
  return 0
}
