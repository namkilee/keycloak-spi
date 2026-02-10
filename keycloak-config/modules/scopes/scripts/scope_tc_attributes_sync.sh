#!/usr/bin/env bash
set -euo pipefail
exec 2>&1

# =========================
# Required envs
# =========================
: "${KCADM_EXEC_MODE:?}"         # docker | kubectl
: "${KEYCLOAK_URL:?}"
: "${KEYCLOAK_AUTH_REALM:?}"
: "${KEYCLOAK_CLIENT_ID:?}"
: "${KEYCLOAK_CLIENT_SECRET:?}"
: "${REALM_ID:?}"                # realm name (not UUID)
: "${SCOPE_ID:?}"                # may be stale if scope recreated
: "${SCOPE_KEY:?}"
: "${SCOPE_NAME:?}"              # actual Keycloak client-scope name
: "${TC_SETS_JSON:?}"

# =========================
# Optional envs
# =========================
: "${KCADM_PATH:=/opt/bitnami/keycloak/bin/kcadm.sh}"

TC_PREFIX_ROOT="${TC_PREFIX_ROOT:-tc}"
SYNC_MODE="${SYNC_MODE:-replace}"
PREFIX="${TC_PREFIX_ROOT}.${SCOPE_NAME}."

KEYCLOAK_TLS_MODE="${KEYCLOAK_TLS_MODE:-truststore}"
KEYCLOAK_CA_CERT_PEM="${KEYCLOAK_CA_CERT_PEM:-/certs/tls.crt}"

KCADM_TRUSTSTORE_DIR="${KCADM_TRUSTSTORE_DIR:-/tmp}"
KCADM_TRUSTSTORE_FILE="${KCADM_TRUSTSTORE_FILE:-${KCADM_TRUSTSTORE_DIR}/kcadm-truststore.jks}"
KCADM_TRUSTSTORE_PASS="${KCADM_TRUSTSTORE_PASS:-keycloak}"
KCADM_TRUSTSTORE_ALIAS="${KCADM_TRUSTSTORE_ALIAS:-keycloak-ca}"

KC_TMP_DIR="${KC_TMP_DIR:-/tmp}"
KC_UPDATED_JSON_PATH="${KC_TMP_DIR}/kc-scope-update-${REALM_ID}-${SCOPE_NAME}.json"

KEYTOOL_BIN="${KEYTOOL_BIN:-/opt/bitnami/java/bin/keytool}"
KCADM_HOME_DIR="${KCADM_HOME_DIR:-/tmp/kcadm-home-${REALM_ID}-${SCOPE_NAME}-${SCOPE_KEY}}"

DEBUG="${DEBUG:-false}"

log() { echo "[$(date -Iseconds)] $*"; }
dbg() { [[ "${DEBUG}" == "true" ]] && log "[DEBUG] $*"; }

# =========================
# Exec wrappers
# =========================
kc_init_exec() {
  case "${KCADM_EXEC_MODE}" in
    docker)
      : "${KEYCLOAK_CONTAINER_NAME:?}"
      KC_EXEC=(docker exec)
      KC_EXEC_I=(docker exec -i)
      KC_TARGET="${KEYCLOAK_CONTAINER_NAME}"
      ;;
    kubectl)
      : "${KEYCLOAK_NAMESPACE:?}"
      : "${KEYCLOAK_POD_SELECTOR:?}"
      KC_TARGET="$(kubectl -n "${KEYCLOAK_NAMESPACE}" get pod -l "${KEYCLOAK_POD_SELECTOR}" -o jsonpath='{.items[0].metadata.name}')"
      [[ -n "${KC_TARGET}" ]] || { echo "No Keycloak pod found" >&2; exit 1; }
      KC_EXEC=(kubectl -n "${KEYCLOAK_NAMESPACE}" exec)
      KC_EXEC_I=(kubectl -n "${KEYCLOAK_NAMESPACE}" exec -i)
      ;;
    *)
      echo "Unsupported KCADM_EXEC_MODE: ${KCADM_EXEC_MODE}" >&2
      exit 1
      ;;
  esac
}

kc_sh() {
  "${KC_EXEC[@]}" "${KC_TARGET}" \
    env HOME="${KCADM_HOME_DIR}" \
    /bin/sh -c "set -e; mkdir -p \"\$HOME\"; $*"
}

# 🔴 FIXED: heredoc 제거, stdin 보존
kc_kcadm() {
  "${KC_EXEC[@]}" "${KC_TARGET}" \
    env HOME="${KCADM_HOME_DIR}" \
    "${KCADM_PATH}" "$@"
}

kc_write_file() {
  local path="$1"
  "${KC_EXEC_I[@]}" "${KC_TARGET}" \
    env HOME="${KCADM_HOME_DIR}" \
    /bin/sh -c "set -e; mkdir -p \"$(dirname "$path")\"; cat > \"$path\""
}

kc_init_exec

# =========================
# Preflight
# =========================
kc_sh "test -x '${KCADM_PATH}' || { echo 'ERROR: KCADM_PATH not executable' >&2; exit 1; }"
kc_sh "command -v python3 >/dev/null || { echo 'ERROR: python3 not found' >&2; exit 1; }"

# =========================
# TLS truststore
# =========================
if [[ "${KEYCLOAK_TLS_MODE}" == "truststore" ]]; then
  kc_sh "
    test -f '${KEYCLOAK_CA_CERT_PEM}' || { echo 'ERROR: cert not found' >&2; exit 1; }
    mkdir -p '${KCADM_TRUSTSTORE_DIR}'
    if [ -f '${KCADM_TRUSTSTORE_FILE}' ] && '${KEYTOOL_BIN}' -list \
        -keystore '${KCADM_TRUSTSTORE_FILE}' \
        -storepass '${KCADM_TRUSTSTORE_PASS}' \
        -alias '${KCADM_TRUSTSTORE_ALIAS}' >/dev/null 2>&1; then
      echo '[OK] truststore already configured'
    else
      rm -f '${KCADM_TRUSTSTORE_FILE}'
      '${KEYTOOL_BIN}' -importcert -noprompt \
        -alias '${KCADM_TRUSTSTORE_ALIAS}' \
        -file '${KEYCLOAK_CA_CERT_PEM}' \
        -keystore '${KCADM_TRUSTSTORE_FILE}' \
        -storepass '${KCADM_TRUSTSTORE_PASS}'
      echo '[OK] truststore created'
    fi
  "
  kc_kcadm config truststore --trustpass "${KCADM_TRUSTSTORE_PASS}" "${KCADM_TRUSTSTORE_FILE}"
fi

# =========================
# kcadm login
# =========================
kc_kcadm config credentials \
  --server "${KEYCLOAK_URL}" \
  --realm "${KEYCLOAK_AUTH_REALM}" \
  --client "${KEYCLOAK_CLIENT_ID}" \
  --secret "${KEYCLOAK_CLIENT_SECRET}"

# =========================
# Resolve scope id by name
# =========================
FOUND_ID="$(kc_kcadm get client-scopes -r "${REALM_ID}" -q "name=${SCOPE_NAME}" | python3 - <<'PY'
import sys, json
arr=json.load(sys.stdin)
print(arr[0]["id"] if arr else "")
PY
)"

[[ -n "${FOUND_ID}" ]] || { echo "ERROR: client-scope not found: ${SCOPE_NAME}" >&2; exit 1; }
[[ "${FOUND_ID}" == "${SCOPE_ID}" ]] || SCOPE_ID="${FOUND_ID}"

# =========================
# Fetch & build payload
# =========================
CURRENT_JSON="$(kc_kcadm get "client-scopes/${SCOPE_ID}" -r "${REALM_ID}")"

TMP_JSON="$(mktemp)"
trap 'rm -f "${TMP_JSON}"' EXIT

CURRENT_JSON="${CURRENT_JSON}" \
TC_SETS_JSON="${TC_SETS_JSON}" \
PREFIX="${PREFIX}" \
SYNC_MODE="${SYNC_MODE}" \
python3 - <<'PY' > "${TMP_JSON}"
import json, os
cur=json.loads(os.environ["CURRENT_JSON"])
tc=json.loads(os.environ["TC_SETS_JSON"])
prefix=os.environ["PREFIX"]

payload={k:cur[k] for k in ("id","name","protocol","description","consentScreenText","includeInTokenScope") if k in cur}

attrs=cur.get("attributes") or {}
attrs={k:v for k,v in attrs.items() if not k.startswith(prefix)}
terms=[]
for k,v in tc.items():
  terms.append({
    "key":k,
    "title":v.get("title",k),
    "version":v["version"],
    "required":bool(v.get("required",False)),
    "url":v.get("url","")
  })
attrs["tc.terms"]=json.dumps(terms, ensure_ascii=False)
payload["attributes"]=attrs
print(json.dumps(payload, ensure_ascii=False))
PY

cat "${TMP_JSON}" | kc_write_file "${KC_UPDATED_JSON_PATH}"
kc_kcadm update "client-scopes/${SCOPE_ID}" -r "${REALM_ID}" -f "${KC_UPDATED_JSON_PATH}"

# =========================
# Verify
# =========================
UPDATED_JSON="$(kc_kcadm get "client-scopes/${SCOPE_ID}" -r "${REALM_ID}")"
echo "${UPDATED_JSON}" | python3 - <<'PY'
import json,sys
attrs=json.load(sys.stdin).get("attributes") or {}
assert "tc.terms" in attrs, "tc.terms missing after update"
PY

log "[OK] tc.terms synced (scope=${SCOPE_NAME})"
