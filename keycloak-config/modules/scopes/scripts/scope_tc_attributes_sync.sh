#!/usr/bin/env bash
set -euo pipefail

# =========================
# Required envs
# =========================
: "${KCADM_PATH:-/opt/bitnami/keycloak/bin/}"
: "${KCADM_EXEC_MODE:?}"         # docker | kubectl
: "${KEYCLOAK_URL:?}"
: "${KEYCLOAK_AUTH_REALM:?}"
: "${KEYCLOAK_CLIENT_ID:?}"
: "${KEYCLOAK_CLIENT_SECRET:?}"
: "${REALM_ID:?}"                # realm name (not UUID)
: "${SCOPE_ID:?}"
: "${SCOPE_KEY:?}"
: "${SCOPE_NAME:?}"              # actual Keycloak client-scope name
: "${TC_SETS_JSON:?}"

# =========================
# Optional envs
# =========================
TC_PREFIX_ROOT="${TC_PREFIX_ROOT:-tc}"
SYNC_MODE="${SYNC_MODE:-replace}"   # replace = tc.<scopeName>.* 삭제 후 재작성
PREFIX="${TC_PREFIX_ROOT}.${SCOPE_NAME}."

# TLS truststore mode:
KEYCLOAK_TLS_MODE="${KEYCLOAK_TLS_MODE:-truststore}"   # truststore|off
KEYCLOAK_CA_CERT_PEM="${KEYCLOAK_CA_CERT_PEM:-/certs/tls.crt}"

KCADM_TRUSTSTORE_DIR="${KCADM_TRUSTSTORE_DIR:-/tmp}"
KCADM_TRUSTSTORE_FILE="${KCADM_TRUSTSTORE_FILE:-${KCADM_TRUSTSTORE_DIR}/kcadm-truststore.jks}"
KCADM_TRUSTSTORE_PASS="${KCADM_TRUSTSTORE_PASS:-keycloak}"
KCADM_TRUSTSTORE_ALIAS="${KCADM_TRUSTSTORE_ALIAS:-keycloak-ca}"

KC_TMP_DIR="${KC_TMP_DIR:-/tmp}"
KC_UPDATED_JSON_PATH="${KC_UPDATED_JSON_PATH:-${KC_TMP_DIR}/kc-scope-update-${SCOPE_ID}.json}"

KEYTOOL_BIN="${KEYTOOL_BIN:-/opt/bitnami/java/bin/keytool}"
KCADM_HOME_DIR="${KCADM_HOME_DIR:-/tmp/kcadm-home-${REALM_ID}-${SCOPE_ID}-${SCOPE_KEY}}"

# =========================
# Exec wrappers (docker/kubectl)
# =========================
kc_init_exec() {
  case "${KCADM_EXEC_MODE}" in
    docker)
      : "${KEYCLOAK_CONTAINER_NAME:?}"
      KC_EXEC=(docker exec "${KEYCLOAK_CONTAINER_NAME}")
      KC_EXEC_I=(docker exec -i "${KEYCLOAK_CONTAINER_NAME}")
      ;;
    kubectl)
      : "${KEYCLOAK_NAMESPACE:?}"
      : "${KEYCLOAK_POD_SELECTOR:?}"
      local pod
      pod="$(kubectl -n "${KEYCLOAK_NAMESPACE}" get pod -l "${KEYCLOAK_POD_SELECTOR}" -o jsonpath='{.items[0].metadata.name}')"
      [[ -n "${pod}" ]] || { echo "No Keycloak pod found" >&2; exit 1; }
      KC_EXEC=(kubectl -n "${KEYCLOAK_NAMESPACE}" exec "${pod}" --)
      KC_EXEC_I=(kubectl -n "${KEYCLOAK_NAMESPACE}" exec -i "${pod}" --)
      ;;
    *)
      echo "Unsupported KCADM_EXEC_MODE: ${KCADM_EXEC_MODE}" >&2
      exit 1
      ;;
  esac
}

kc_sh() {
  "${KC_EXEC[@]}" /bin/sh -lc "set -e; HOME='${KCADM_HOME_DIR}'; mkdir -p \"\$HOME\"; $*"
}

kc_kcadm() {
  "${KC_EXEC[@]}" /bin/sh -lc '
    set -e
    HOME="$1"
    shift
    mkdir -p "$HOME"
    exec "$@"
  ' -- "${KCADM_HOME_DIR}" "${KCADM_PATH}" "$@"
}

kc_write_file() {
  local path="$1"
  "${KC_EXEC_I[@]}" /bin/sh -lc "set -e; HOME='${KCADM_HOME_DIR}'; mkdir -p \"\$HOME\"; mkdir -p \"$(dirname "$path")\" && cat > \"$path\""
}

kc_init_exec

# =========================
# TLS truststore setup
# =========================
if [[ "${KEYCLOAK_TLS_MODE}" == "truststore" ]]; then
  kc_sh "
    test -f '${KEYCLOAK_CA_CERT_PEM}' || { echo 'ERROR: cert not found: ${KEYCLOAK_CA_CERT_PEM}' >&2; exit 1; }
    if [ ! -x '${KEYTOOL_BIN}' ]; then
      echo 'ERROR: keytool not executable at ${KEYTOOL_BIN}' >&2
      exit 1
    fi
    mkdir -p '${KCADM_TRUSTSTORE_DIR}'
    if [ -f '${KCADM_TRUSTSTORE_FILE}' ] && '${KEYTOOL_BIN}' -list -keystore '${KCADM_TRUSTSTORE_FILE}' -storepass '${KCADM_TRUSTSTORE_PASS}' -alias '${KCADM_TRUSTSTORE_ALIAS}' >/dev/null 2>&1; then
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
elif [[ "${KEYCLOAK_TLS_MODE}" == "off" ]]; then
  :
else
  echo "Unsupported KEYCLOAK_TLS_MODE: ${KEYCLOAK_TLS_MODE} (use truststore|off)" >&2
  exit 1
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
# Fetch current client-scope JSON
# =========================
CURRENT_JSON="$(kc_kcadm get "client-scopes/${SCOPE_ID}" -r "${REALM_ID}")"
[[ -n "${CURRENT_JSON}" ]] || { echo "ERROR: CURRENT_JSON is empty (scope not found?)" >&2; exit 1; }

# =========================
# Build updated *minimal* ClientScopeRepresentation on HOST
# =========================
TMP_JSON="$(mktemp)"
trap 'rm -f "${TMP_JSON}"' EXIT

CURRENT_JSON="${CURRENT_JSON}" \
TC_SETS_JSON="${TC_SETS_JSON}" \
PREFIX="${PREFIX}" \
SYNC_MODE="${SYNC_MODE}" \
python3 - <<'PY' > "${TMP_JSON}"
import json, os

current = json.loads(os.environ["CURRENT_JSON"])
tc_sets = json.loads(os.environ["TC_SETS_JSON"])
prefix = os.environ["PREFIX"]
mode = os.environ.get("SYNC_MODE", "replace")

# ClientScopeRepresentation에서 우리가 안전하게 PUT할 필드만 추림
# (버전에 따라 read-only/불필요 필드가 섞이면 PUT에서 죽을 수 있음)
payload = {}

# id/name/protocol은 거의 항상 필요/안전
for k in ("id", "name", "protocol", "description", "consentScreenText", "includeInTokenScope"):
    if k in current and current[k] is not None:
        payload[k] = current[k]

# attributes는 ClientScope에서 일반적으로 Map<String,String>로 다루는 편이 안전
attrs = current.get("attributes") or {}
if not isinstance(attrs, dict):
    attrs = {}

# replace면 legacy prefix(tc.<scopeName>.*) 삭제 + tc.terms 재작성
if mode == "replace":
    attrs = {k: v for k, v in attrs.items() if not str(k).startswith(prefix)}
    attrs.pop("tc.terms", None)

# tc_sets(termKey -> cfg)를 terms 배열로 만들고, 이를 "문자열"로 저장
terms = []
for term_key, cfg in (tc_sets or {}).items():
    if not isinstance(cfg, dict):
        continue
    title = cfg.get("title") or term_key
    required = bool(cfg.get("required", False))
    version = cfg.get("version") or "unknown"
    url = cfg.get("url") or ""
    terms.append({
        "key": str(term_key),
        "title": str(title),
        "version": str(version),
        "url": str(url) if url else "",
        "required": required,
    })

attrs["tc.terms"] = json.dumps(terms, ensure_ascii=False)

payload["attributes"] = attrs

print(json.dumps(payload))
PY

# host-side validation
python3 -m json.tool "${TMP_JSON}" >/dev/null || {
  echo "ERROR: invalid json generated on host"
  sed -n '1,5p' "${TMP_JSON}" >&2
  tail -n 5 "${TMP_JSON}" >&2
  exit 1
}

# Stream to container/pod
cat "${TMP_JSON}" | kc_write_file "${KC_UPDATED_JSON_PATH}"
kc_sh "test -s '${KC_UPDATED_JSON_PATH}' || { echo 'ERROR: updated json file empty: ${KC_UPDATED_JSON_PATH}' >&2; exit 1; }"

# =========================
# Update client-scope with minimal representation
# =========================
kc_kcadm update "client-scopes/${SCOPE_ID}" -r "${REALM_ID}" -f "${KC_UPDATED_JSON_PATH}"

echo "Synced terms to attribute tc.terms (mode=${SYNC_MODE})"
echo "Legacy prefix cleanup applied: ${PREFIX} (mode=replace only)"
echo "Scope: id=${SCOPE_ID}, key=${SCOPE_KEY}, name=${SCOPE_NAME}"
echo "Updated JSON path: ${KC_UPDATED_JSON_PATH} (inside ${KCADM_EXEC_MODE} runtime)"
