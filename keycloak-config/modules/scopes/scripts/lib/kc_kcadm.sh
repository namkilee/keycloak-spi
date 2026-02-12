#!/usr/bin/env bash
set -Eeuo pipefail

log() { echo "[$(date -Is)] $*" >&2; }
die() { log "FATAL: $*"; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

: "${KCADM_EXEC_MODE:?}"   # docker|kubectl
: "${KCADM_PATH:?}"        # e.g. /opt/bitnami/keycloak/bin/kcadm.sh

# 컨테이너/파드 내부 HOME: 랜덤 말고 고정 추천 (apply 중 재사용)
KCADM_HOME_DIR="${KCADM_HOME_DIR:-/tmp/kcadm_home_terraform}"

# CA 경로/비번 (docker 내부 /certs 에 있다고 했으니 기본값을 /certs/ca.pem 으로)
KEYCLOAK_CA_PEM_PATH="${KEYCLOAK_CA_PEM_PATH:-/certs/ca.pem}"
KCADM_TRUSTSTORE_PASS="${KCADM_TRUSTSTORE_PASS:-changeit}"

# ---------------------------
# Low-level exec wrappers
# ---------------------------
kc_shell() {
  # usage: kc_shell '<shell script>'
  local script="$1"

  case "$KCADM_EXEC_MODE" in
    docker)
      : "${KEYCLOAK_CONTAINER_NAME:?KEYCLOAK_CONTAINER_NAME is required for docker mode}"
      need_cmd docker
      docker exec -i "$KEYCLOAK_CONTAINER_NAME" \
        env HOME="$KCADM_HOME_DIR" \
        /bin/sh -lc "set -e; mkdir -p \"\$HOME\"; $script"
      ;;
    kubectl)
      : "${KEYCLOAK_NAMESPACE:?KEYCLOAK_NAMESPACE is required for kubectl mode}"
      : "${KEYCLOAK_POD_SELECTOR:?KEYCLOAK_POD_SELECTOR is required for kubectl mode}"
      need_cmd kubectl
      local pod
      pod="$(kubectl -n "$KEYCLOAK_NAMESPACE" get pod -l "$KEYCLOAK_POD_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
      [[ -n "$pod" ]] || die "No pod found with selector: $KEYCLOAK_POD_SELECTOR in ns=$KEYCLOAK_NAMESPACE"
      kubectl -n "$KEYCLOAK_NAMESPACE" exec -i "$pod" -- \
        env HOME="$KCADM_HOME_DIR" \
        /bin/sh -lc "set -e; mkdir -p \"\$HOME\"; $script"
      ;;
    *)
      die "Unknown KCADM_EXEC_MODE=$KCADM_EXEC_MODE (expected docker|kubectl)"
      ;;
  esac
}

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
      pod="$(kubectl -n "$KEYCLOAK_NAMESPACE" get pod -l "$KEYCLOAK_POD_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
      [[ -n "$pod" ]] || die "No pod found with selector: $KEYCLOAK_POD_SELECTOR in ns=$KEYCLOAK_NAMESPACE"
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

# ---------------------------
# Truststore setup for kcadm (fix PKIX)
# ---------------------------
kc_ensure_truststore() {
  # CA 파일이 없으면(예: http or 이미 신뢰됨) 그냥 스킵
  if ! kc_shell "[ -f \"${KEYCLOAK_CA_PEM_PATH}\" ]"; then
    log "WARN: CA pem not found at ${KEYCLOAK_CA_PEM_PATH}; skip truststore config"
    return 0
  fi

  local ts="${KCADM_HOME_DIR}/truststore.jks"
  local marker="${KCADM_HOME_DIR}/.truststore_configured"

  # 이미 구성했으면 스킵 (apply 중 반복 실행 방지)
  if kc_shell "[ -f \"${marker}\" ]"; then
    return 0
  fi

  log "Configuring kcadm truststore (ca=${KEYCLOAK_CA_PEM_PATH})..."

  # keytool 경로: bitnami 우선, 없으면 PATH
  kc_shell "
    set -e
    KEYTOOL='/opt/bitnami/java/bin/keytool'
    if [ ! -x \"\$KEYTOOL\" ]; then KEYTOOL='keytool'; fi
    \"\$KEYTOOL\" -importcert -noprompt \
      -alias keycloak-ca \
      -file '${KEYCLOAK_CA_PEM_PATH}' \
      -keystore '${ts}' \
      -storepass '${KCADM_TRUSTSTORE_PASS}' >/dev/null 2>&1 || true
  "

  # kcadm에 truststore 등록
  kc_exec config truststore --trustpass "${KCADM_TRUSTSTORE_PASS}" "${ts}" >/dev/null

  # marker
  kc_shell "set -e; echo ok > '${marker}'"
}

# ---------------------------
# Secret handling for client credentials
# ---------------------------
_read_client_secret() {
  if [[ -n "${KEYCLOAK_CLIENT_SECRET_FILE:-}" ]]; then
    [[ -f "$KEYCLOAK_CLIENT_SECRET_FILE" ]] || die "KEYCLOAK_CLIENT_SECRET_FILE not found: $KEYCLOAK_CLIENT_SECRET_FILE"
    cat "$KEYCLOAK_CLIENT_SECRET_FILE"
    return 0
  fi
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

  # PKIX 방지: credentials 전에 truststore 설정
  kc_ensure_truststore

  log "Login via kcadm (client credentials)..."
  with_retry "$retries" "$backoff" kc_exec config credentials \
    --server "$KEYCLOAK_URL" \
    --realm "$KEYCLOAK_AUTH_REALM" \
    --client "$KEYCLOAK_CLIENT_ID" \
    --secret "$secret" >/dev/null
}
