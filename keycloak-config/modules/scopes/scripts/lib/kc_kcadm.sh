#!/usr/bin/env bash
set -Eeuo pipefail

log() { echo "[$(date -Is)] $*" >&2; }
die() { log "FATAL: $*"; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

: "${KCADM_EXEC_MODE:?}"   # docker|kubectl
: "${KCADM_PATH:?}"        # e.g. /opt/bitnami/keycloak/bin/kcadm.sh

# 컨테이너/파드 내부 HOME (host mktemp 경로 사용 금지)
KCADM_HOME_DIR="${KCADM_HOME_DIR:-/tmp/kcadm_home.$RANDOM.$RANDOM}"

kc_exec() {
  case "$KCADM_EXEC_MODE" in
    docker)
      : "${KEYCLOAK_CONTAINER_NAME:?KEYCLOAK_CONTAINER_NAME is required for docker mode}"
      need_cmd docker
      docker exec -i "$KEYCLOAK_CONTAINER_NAME" \
        env HOME="$KCADM_HOME_DIR" \
        /bin/sh -lc 'set -e; mkdir -p "$HOME"; exec "$0" "$@"' \
        "$KCADM_PATH" "$@"
      ;;
    kubectl)
      : "${KEYCLOAK_NAMESPACE:?KEYCLOAK_NAMESPACE is required for kubectl mode}"
      : "${KEYCLOAK_POD_SELECTOR:?KEYCLOAK_POD_SELECTOR is required for kubectl mode}"
      need_cmd kubectl
      local pod
      pod="$(kubectl -n "$KEYCLOAK_NAMESPACE" get pod -l "$KEYCLOAK_POD_SELECTOR" -o jsonpath='{.items[0].metadata.name}')"
      [[ -n "$pod" ]] || die "No pod found with selector: $KEYCLOAK_POD_SELECTOR"
      kubectl -n "$KEYCLOAK_NAMESPACE" exec -i "$pod" -- \
        env HOME="$KCADM_HOME_DIR" \
        /bin/sh -lc 'set -e; mkdir -p "$HOME"; exec "$0" "$@"' \
        "$KCADM_PATH" "$@"
      ;;
    *)
      die "Unknown KCADM_EXEC_MODE=$KCADM_EXEC_MODE (expected docker|kubectl)"
      ;;
  esac
}

with_retry() {
  local max="$1"; shift
  local backoff_ms="$1"; shift
  local i=1 rc=0

  while true; do
    if "$@"; then return 0; fi
    rc=$?
    if (( i >= max )); then return "$rc"; fi

    local ms=$(( backoff_ms * (2 ** (i-1)) ))
    (( ms > 5000 )) && ms=5000
    local sleep_sec
    sleep_sec="$(awk "BEGIN { printf \"%.3f\", ${ms}/1000 }")"

    log "WARN: failed rc=$rc retry $i/$max after ${sleep_sec}s: $*"
    sleep "$sleep_sec"
    i=$((i+1))
  done
}

# ✅ secret은 env(KEYCLOAK_CLIENT_SECRET) 대신 파일(KEYCLOAK_CLIENT_SECRET_FILE)을 우선 사용
_read_client_secret() {
  if [[ -n "${KEYCLOAK_CLIENT_SECRET_FILE:-}" ]]; then
    [[ -f "$KEYCLOAK_CLIENT_SECRET_FILE" ]] || die "KEYCLOAK_CLIENT_SECRET_FILE not found: $KEYCLOAK_CLIENT_SECRET_FILE"
    cat "$KEYCLOAK_CLIENT_SECRET_FILE"
    return 0
  fi
  # fallback (가능하면 사용 안 하는 걸 추천)
  echo -n "${KEYCLOAK_CLIENT_SECRET:-}"
}

kc_login_client_credentials() {
  : "${KEYCLOAK_URL:?}"
  : "${KEYCLOAK_AUTH_REALM:?}"
  : "${KEYCLOAK_CLIENT_ID:?}"

  local secret
  secret="$(_read_client_secret)"
  [[ -n "$secret" ]] || die "Missing client secret (set KEYCLOAK_CLIENT_SECRET_FILE or KEYCLOAK_CLIENT_SECRET)"

  local retries="${1:-5}"
  local backoff="${2:-400}"

  log "Login via kcadm (client credentials)..."
  with_retry "$retries" "$backoff" kc_exec config credentials \
    --server "$KEYCLOAK_URL" \
    --realm "$KEYCLOAK_AUTH_REALM" \
    --client "$KEYCLOAK_CLIENT_ID" \
    --secret "$secret" >/dev/null
}
