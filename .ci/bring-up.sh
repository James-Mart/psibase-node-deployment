#!/usr/bin/env bash
set -euo pipefail

# Operator-runnable full-stack check. Exports the CI compose environment,
# proves isolation, then starts the node the same way an operator does.

if [[ $# -gt 0 ]]; then
  echo "bring-up: takes no arguments" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=.ci/lib/entrypoint-branch-assert.sh
source "$SCRIPT_DIR/lib/entrypoint-branch-assert.sh"

ENV_CI="$SCRIPT_DIR/.env.ci"
READY_TIMEOUT=180
NOT_FOUND_GRACE=15
ACME_TIMEOUT=60
# Must match HTTPS_PROXY in docker-compose.ci.yml.
ACME_PROXY_ADDRESS="127.0.0.1:9"
DECOY_VOLUME="psibase-node-deployment_psinode-volume"
DECOY_NETWORK="psibase_net"

export COMPOSE_FILE="docker-compose.yml:docker-compose.ci.yml"
export COMPOSE_PROJECT_NAME=psibase-node-ci
export COMPOSE_ENV_FILES="$ENV_CI"

HOST="$(grep -E '^HOST=' "$ENV_CI" | head -1 | cut -d= -f2-)"
if [[ -z "$HOST" ]]; then
  echo "bring-up: HOST is missing from $ENV_CI" >&2
  exit 1
fi

if [[ -z "${AUTHELIA_IMAGE:-}" ]]; then
  AUTHELIA_IMAGE="$(grep -E '^AUTHELIA_IMAGE=' "$ENV_CI" | head -1 | cut -d= -f2-)"
  export AUTHELIA_IMAGE
fi

X_HOST="x-logs.${HOST}"
CURL_BODY=""
CURL_HEADERS=""
LAST_PROBE_URL=""
LAST_PROBE_CODE=""
CLEANED=0
CREATED_DECOY_VOLUME=0
CREATED_DECOY_NETWORK=0
DECOYS_INSTALLED=0
DECOY_VOLUME_CREATED_AT=""
DECOY_NETWORK_ID=""

dump_diagnostics() {
  echo "=== bring-up diagnostics ===" >&2
  echo "--- docker compose ps ---" >&2
  docker compose ps -a >&2 || true

  echo "--- per-service logs ---" >&2
  local svc
  while IFS= read -r svc; do
    [[ -n "$svc" ]] || continue
    echo "---- ${svc} ----" >&2
    docker compose logs --no-color --timestamps "$svc" >&2 || true
  done < <(docker compose config --services 2>/dev/null || true)

  echo "--- resolved compose config ---" >&2
  docker compose config >&2 || true

  echo "--- last probe ---" >&2
  echo "url=${LAST_PROBE_URL:-none} status=${LAST_PROBE_CODE:-none}" >&2
  if [[ -n "$CURL_HEADERS" && -f "$CURL_HEADERS" ]]; then
    echo "headers:" >&2
    cat "$CURL_HEADERS" >&2 || true
  fi
  if [[ -n "$CURL_BODY" && -f "$CURL_BODY" ]]; then
    echo "body:" >&2
    cat "$CURL_BODY" >&2 || true
    echo >&2
  fi
}

die() {
  echo "bring-up: $*" >&2
  dump_diagnostics
  exit 1
}

remove_owned_decoys() {
  if [[ "$CREATED_DECOY_VOLUME" -eq 1 ]]; then
    docker volume rm "$DECOY_VOLUME" || true
    CREATED_DECOY_VOLUME=0
  fi
  if [[ "$CREATED_DECOY_NETWORK" -eq 1 ]]; then
    docker network rm "$DECOY_NETWORK" || true
    CREATED_DECOY_NETWORK=0
  fi
}

decoys_survived() {
  local created_at network_id
  created_at="$(docker volume inspect -f '{{.CreatedAt}}' "$DECOY_VOLUME" 2>/dev/null || true)"
  network_id="$(docker network inspect -f '{{.Id}}' "$DECOY_NETWORK" 2>/dev/null || true)"
  if [[ "$created_at" != "$DECOY_VOLUME_CREATED_AT" ]]; then
    echo "bring-up: production decoy volume ${DECOY_VOLUME} was created, replaced, or removed" >&2
    echo "  want CreatedAt=${DECOY_VOLUME_CREATED_AT}" >&2
    echo "  got  CreatedAt=${created_at:-missing}" >&2
    return 1
  fi
  if [[ "$network_id" != "$DECOY_NETWORK_ID" ]]; then
    echo "bring-up: production decoy network ${DECOY_NETWORK} was created, replaced, or removed" >&2
    echo "  want Id=${DECOY_NETWORK_ID}" >&2
    echo "  got  Id=${network_id:-missing}" >&2
    return 1
  fi
  return 0
}

install_decoys() {
  if docker volume inspect "$DECOY_VOLUME" >/dev/null 2>&1; then
    DECOY_VOLUME_CREATED_AT="$(docker volume inspect -f '{{.CreatedAt}}' "$DECOY_VOLUME")"
  else
    docker volume create "$DECOY_VOLUME" >/dev/null
    CREATED_DECOY_VOLUME=1
    DECOY_VOLUME_CREATED_AT="$(docker volume inspect -f '{{.CreatedAt}}' "$DECOY_VOLUME")"
  fi

  if docker network inspect "$DECOY_NETWORK" >/dev/null 2>&1; then
    DECOY_NETWORK_ID="$(docker network inspect -f '{{.Id}}' "$DECOY_NETWORK")"
  else
    docker network create \
      --driver bridge \
      --subnet 172.30.0.0/24 \
      --gateway 172.30.0.1 \
      "$DECOY_NETWORK" >/dev/null
    CREATED_DECOY_NETWORK=1
    DECOY_NETWORK_ID="$(docker network inspect -f '{{.Id}}' "$DECOY_NETWORK")"
  fi
  DECOYS_INSTALLED=1
}

cleanup() {
  local rc=$?
  if [[ "$CLEANED" -eq 1 ]]; then
    return
  fi
  CLEANED=1
  rm -f "$CURL_BODY" "$CURL_HEADERS"
  echo "Tearing down CI stack..."
  docker compose down --volumes --remove-orphans || true

  if [[ "$DECOYS_INSTALLED" -eq 1 ]]; then
    if ! decoys_survived; then
      remove_owned_decoys
      if [[ $rc -eq 0 ]]; then
        exit 1
      fi
      return
    fi
  fi
  remove_owned_decoys
}

https_get() {
  local host="$1"
  local url="$2"
  local code
  LAST_PROBE_URL="$url"
  code="$(curl -sS -k \
    --connect-timeout 2 \
    --max-time 10 \
    --resolve "${host}:443:127.0.0.1" \
    -o "$CURL_BODY" \
    -D "$CURL_HEADERS" \
    -w '%{http_code}' \
    "$url" || true)"
  LAST_PROBE_CODE="${code:-000}"
  echo "$LAST_PROBE_CODE"
}

http_get() {
  local host="$1"
  local url="$2"
  local code
  LAST_PROBE_URL="$url"
  code="$(curl -sS \
    --connect-timeout 2 \
    --max-time 10 \
    --resolve "${host}:80:127.0.0.1" \
    -o "$CURL_BODY" \
    -D "$CURL_HEADERS" \
    -w '%{http_code}' \
    "$url" || true)"
  LAST_PROBE_CODE="${code:-000}"
  echo "$LAST_PROBE_CODE"
}

header_value() {
  local name="$1"
  grep -i "^${name}:" "$CURL_HEADERS" | tail -1 | sed "s/^[A-Za-z0-9-]*:[[:space:]]*//;s/\r$//" || true
}

is_traefik_404() {
  local code="$1"
  if [[ "$code" == "404" ]]; then
    return 0
  fi
  grep -q '404 page not found' "$CURL_BODY" 2>/dev/null
}

# First-run psinode 302s / to x-admin (Boost.Beast) instead of serving 2xx.
# That is psinode answering; Traefik 404/502 are not.
is_psinode_response() {
  local code="$1"
  if is_traefik_404 "$code" || [[ "$code" == "502" || "$code" == "503" ]]; then
    return 1
  fi
  if [[ "$code" =~ ^2[0-9][0-9]$ ]]; then
    return 0
  fi
  if [[ "$code" == "302" ]] && grep -qi '^server:[[:space:]]*Boost.Beast' "$CURL_HEADERS"; then
    return 0
  fi
  return 1
}

wait_for_traefik() {
  local deadline=$((SECONDS + READY_TIMEOUT))
  echo "Waiting for Traefik to answer on 443..."
  LAST_PROBE_URL="https://${HOST}/"
  while ((SECONDS < deadline)); do
    if curl -sk \
      --connect-timeout 2 \
      --max-time 5 \
      --resolve "${HOST}:443:127.0.0.1" \
      -o /dev/null \
      "https://${HOST}/"; then
      echo "Traefik answered."
      return 0
    fi
    sleep 2
  done
  LAST_PROBE_CODE="000"
  die "timed out waiting for Traefik to answer on 443"
}

assert_psinode_443() {
  local deadline=$((SECONDS + READY_TIMEOUT))
  local not_found_deadline=$((SECONDS + NOT_FOUND_GRACE))
  local code
  echo "Asserting https://${HOST}/ returns psinode..."
  while ((SECONDS < deadline)); do
    code="$(https_get "$HOST" "https://${HOST}/")"
    LAST_PROBE_CODE="$code"
    if is_traefik_404 "$code"; then
      if ((SECONDS < not_found_deadline)); then
        sleep 2
        continue
      fi
      die "443 assertion failed: Traefik 404 (routing), want psinode (status=${code})"
    fi
    if [[ "$code" == "502" || "$code" == "503" ]]; then
      sleep 2
      continue
    fi
    if is_psinode_response "$code"; then
      echo "443 ok (status ${code})"
      return 0
    fi
    die "443 assertion failed: status ${code}, want psinode (not 502, not Traefik 404)"
  done
  die "443 assertion failed: psinode not serving after ${READY_TIMEOUT}s (last status ${code:-none})"
}

assert_http_301() {
  local code location
  echo "Asserting http://${HOST}/ returns 301 to HTTPS..."
  code="$(http_get "$HOST" "http://${HOST}/")"
  LAST_PROBE_CODE="$code"
  location="$(header_value Location)"
  if [[ "$code" != "301" ]] || [[ "$location" != https://* ]]; then
    die "port 80 assertion failed: want 301 to https://*, got status=${code} location=${location}"
  fi
  echo "80 ok (301 ${location})"
}

assert_x_auth_redirect() {
  local deadline=$((SECONDS + READY_TIMEOUT))
  local code location
  echo "Asserting https://${X_HOST}/ redirects to x-auth..."
  while ((SECONDS < deadline)); do
    code="$(https_get "$X_HOST" "https://${X_HOST}/")"
    LAST_PROBE_CODE="$code"
    location="$(header_value Location)"
    if [[ "$code" == "502" || "$code" == "503" ]]; then
      sleep 2
      continue
    fi
    if [[ "$code" == "302" ]] && [[ "$location" == *"x-auth.${HOST}"* ]]; then
      echo "x-* ok (302 ${location})"
      return 0
    fi
    die "x-* assertion failed: want 302 to x-auth.${HOST} (not 502), got status=${code} location=${location}"
  done
  die "x-* assertion failed: Authelia not redirecting after ${READY_TIMEOUT}s (last status ${code:-none})"
}

read_psinode_argv() {
  docker compose exec -T psinode cat /proc/1/cmdline | tr '\0' ' '
}

assert_entrypoint_branch() {
  local branch="$1"
  local argv
  echo "Asserting psinode entrypoint branch (${branch}) from /proc/1/cmdline..."
  if ! argv="$(read_psinode_argv)"; then
    die "entrypoint branch assertion failed (${branch}): could not read psinode argv from /proc/1/cmdline"
  fi
  if ! assert_psinode_argv_branch "$branch" "$argv"; then
    die "entrypoint branch assertion failed (${branch}): see message above (argv=${argv})"
  fi
  echo "entrypoint branch ok (${branch})"
}

assert_softhsm_token() {
  local slots
  echo "Asserting SoftHSM token is present..."
  slots="$(docker compose exec -T softhsm softhsm2-util --show-slots)"
  if ! grep -q 'psibase production SoftHSM' <<<"$slots"; then
    echo "$slots" >&2
    die "SoftHSM token assertion failed: token label not found"
  fi
  echo "SoftHSM token ok"
}

# Certificates are the knowing gap: issuance must fail without reaching a real
# CA or DNS provider. Traefik still names Let's Encrypt in its logs because the
# shipped static config still configures it, so the evidence is where the
# request died — at the local proxy, before leaving the container.
assert_acme_blocked() {
  local deadline=$((SECONDS + ACME_TIMEOUT))
  local logs=""
  echo "Asserting certificate issuance never reached a real CA..."
  while ((SECONDS < deadline)); do
    logs="$(docker compose logs --no-color reverse-proxy 2>/dev/null || true)"
    if grep -q 'urn:ietf:params:acme:error' <<<"$logs"; then
      echo "$logs" >&2
      die "ACME assertion failed: a real CA answered (ACME problem document in Traefik logs)"
    fi
    if grep -q 'proxyconnect' <<<"$logs" &&
      grep -qE "${ACME_PROXY_ADDRESS//./\\.}([^0-9]|$)" <<<"$logs"; then
      echo "ACME ok (issuance refused at ${ACME_PROXY_ADDRESS}, nothing left the container)"
      return 0
    fi
    sleep 2
  done
  echo "$logs" >&2
  die "ACME assertion failed: no proxy-refused issuance attempt in Traefik logs after ${ACME_TIMEOUT}s"
}

assert_guard_refuses_production() {
  local log
  echo "Checking isolation guard refuses a production render..."
  if log="$(env -u COMPOSE_FILE -u COMPOSE_PROJECT_NAME "$SCRIPT_DIR/assert-isolated.sh" 2>&1)"; then
    echo "$log" >&2
    die "isolation guard accepted a production render (want refuse)"
  fi
  echo "$log" >&2
  if ! grep -q 'assert-isolated: refused' <<<"$log"; then
    die "isolation guard failed without a refusal (unexpected error)"
  fi
  echo "Isolation guard refused the production render."
}

echo "Installing production-named decoys (created only if missing)..."
install_decoys
trap 'remove_owned_decoys' EXIT

assert_guard_refuses_production

echo "Checking isolation of the CI stack..."
"$SCRIPT_DIR/assert-isolated.sh"

CURL_BODY="$(mktemp)"
CURL_HEADERS="$(mktemp)"
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

password="${CI_ADMIN_PASSWORD:-}"
if [[ -z "$password" ]]; then
  password="$(openssl rand -base64 24 | tr -d '\n')"
fi

echo "Provisioning admin auth (ci-admin)..."
printf '%s\n' "$password" | "$REPO_ROOT/.setup/setup-admin-auth.sh" --username ci-admin --password-stdin
unset password

echo "Starting node via .scripts/restart-node-fresh.sh..."
"$REPO_ROOT/.scripts/restart-node-fresh.sh"

wait_for_traefik
assert_psinode_443
assert_entrypoint_branch first-run

echo "Restarting node via .scripts/restart-node.sh (preserving volume)..."
"$REPO_ROOT/.scripts/restart-node.sh"

wait_for_traefik
assert_psinode_443
assert_entrypoint_branch resume

assert_http_301
assert_x_auth_redirect
assert_softhsm_token
assert_acme_blocked

echo "bring-up: ok"
