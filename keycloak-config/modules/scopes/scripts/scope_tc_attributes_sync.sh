#!/usr/bin/env bash
set -euo pipefail

: "${KCADM_PATH:?}"
: "${KCADM_EXEC_MODE:?}"         # docker | kubectl
: "${KEYCLOAK_URL:?}"
: "${KEYCLOAK_AUTH_REALM:?}"
: "${KEYCLOAK_CLIENT_ID:?}"
: "${KEYCLOAK_CLIENT_SECRET:?}"
: "${REALM_ID:?}"
: "${SCOPE_ID:?}"
: "${SCOPE_KEY:?}"
: "${TC_SETS_JSON:?}"

TC_PREFIX_ROOT="${TC_PREFIX_ROOT:-tc}"
SYNC_MODE="${SYNC_MODE:-replace}"   # replace = 삭제 포함 동기화
PREFIX="${TC_PREFIX_ROOT}.${SCOPE_KEY}."

# TLS truststore mode (optional)
# - truststore: create/import CA cert into JKS and configure kcadm truststore (recommended)
# - off: do nothing (use only if KEYCLOAK_URL is http:// or cert is publicly trusted)
KEYCLOAK_TLS_MODE="${KEYCLOAK_TLS_MODE:-truststore}"
KEYCLOAK_CA_CERT_PEM="${KEYCLOAK_CA_CERT_PEM:-}"      # must exist inside container/pod

KCADM_TRUSTSTORE_DIR="${KCADM_TRUSTSTORE_DIR:-/tmp}"
KCADM_TRUSTSTORE_FILE="${KCADM_TRUSTSTORE_FILE:-${KCADM_TRUSTSTORE_DIR}/kcadm-truststore.jks}"
KCADM_TRUSTSTORE_PASS="${KCADM_TRUSTSTORE_PASS:-changeit}"
KCADM_TRUSTSTORE_ALIAS="${KCADM_TRUSTSTORE_ALIAS:-keycloak-ca}"

KC_TMP_DIR="${KC_TMP_DIR:-/tmp}"
KC_UPDATED_JSON_PATH="${KC_UPDATED_JSON_PATH:-${KC_TMP_DIR}/kc-scope-update-${SCOPE_ID}.json}"

# ----------------------------
# Common exec utils (docker/kubectl)
# ----------------------------
kc_init_exec() {
  case "${KCADM_EXEC_MODE}" in
    docker)
      : "${KEYCLOAK_CONTAINER_NAME:?}"
      KC_EXEC=(docker exec "${KEYCLOAK_CONTAINER_NAME}")
      ;;
    kubectl)
      : "${KEYCLOAK_NAMESPACE:?}"
      : "${KEYCLOAK_POD_SELECTOR:?}"
      local pod
      pod="$(kubectl -n "${KEYCLOAK_NAMESPACE}" get pod -l "${KEYCLOAK_POD_SELECTOR}" -o jsonpath='{.items[0].metadata.name}')"
      [[ -n "${pod}" ]] || { echo "No Keycloak pod found" >&2; exit 1; }
      KC_EXEC=(kubectl -n "${KEYCLOAK_NAMESPACE}" exec "${pod}" --)
      ;;
    *)
      echo "Unsupported KCADM_EXEC_MODE: ${KCADM_EXEC_MODE}" >&2
      exit 1
      ;;
  esac
}

# Run kcadm inside container/pod
kc_kcadm() {
  "${KC_EXEC[@]}" "${KCADM_PATH}" "$@"
}

# Run /bin/sh -lc inside container/pod (for keytool, file writes, etc.)
kc_sh() {
  "${KC_EXEC[@]}" /bin/sh -lc "$*"
}

# Write a file inside container/pod using stdin (robust for terraform local-exec)
# Usage: echo "content" | kc_write_file "/tmp/x.json"
kc_write_file() {
  local path="$1"
  kc_sh "mkdir -p '$(dirname "$path")' && cat > '$path'"
}

kc_init_exec

# ----------------------------
# TLS truststore setup (optional)
# ----------------------------
if [[ "${KEYCLOAK_TLS_MODE}" == "truststore" ]]; then
  if [[ -z "${KEYCLOAK_CA_CERT_PEM}" ]]; then
    cat >&2 <<EOF
ERROR: KEYCLOAK_TLS_MODE=truststore requires KEYCLOAK_CA_CERT_PEM (path inside container/pod).
Because kcadm runs inside ${KCADM_EXEC_MODE}, this must be a path that exists inside that runtime.
EOF
    exit 1
  fi

  # Create/import truststore inside container/pod
  kc_sh "
    set -e
    test -f '${KEYCLOAK_CA_CERT_PEM}' || { echo 'ERROR: cert not found: ${KEYCLOAK_CA_CERT_PEM}' >&2; exit 1; }
    mkdir -p '${KCADM_TRUSTSTORE_DIR}'
    if [ -f '${KCADM_TRUSTSTORE_FILE}' ] && keytool -list -keystore '${KCADM_TRUSTSTORE_FILE}' -storepass '${KCADM_TRUSTSTORE_PASS}' -alias '${KCADM_TRUSTSTORE_ALIAS}' >/dev/null 2>&1; then
      echo '[OK] truststore already configured'
    else
      rm -f '${KCADM_TRUSTSTORE_FILE}'
      keytool -importcert -noprompt \
        -alias '${KCADM_TRUSTSTORE_ALIAS}' \
        -file '${KEYCLOAK_CA_CERT_PEM}' \
        -keystore '${KCADM_TRUSTSTORE_FILE}' \
        -storepass '${KCADM_TRUSTSTORE_PASS}'
    fi
  "

  # Point kcadm to truststore
  kc_kcadm config truststore --trustpass "${KCADM_TRUSTSTORE_PASS}" "${KCADM_TRUSTSTORE_FILE}"

elif [[ "${KEYCLOAK_TLS_MODE}" == "off" ]]; then
  :
else
  echo "Unsupported KEYCLOAK_TLS_MODE: ${KEYCLOAK_TLS_MODE} (use truststore|off)" >&2
  exit 1
fi

# ----------------------------
# kcadm login
# ----------------------------
kc_kcadm config credentials \
  --server "${KEYCLOAK_URL}" \
  --realm "${KEYCLOAK_AUTH_REALM}" \
  --client "${KEYCLOAK_CLIENT_ID}" \
  --secret "${KEYCLOAK_CLIENT_SECRET}"

# ----------------------------
# Fetch current client-scope JSON
# ----------------------------
CURRENT_JSON="$(kc_kcadm get "client-scopes/${SCOPE_ID}" -r "${REALM_ID}")"

# ----------------------------
# Build updated JSON on host (python), then stream into container/pod file
# ----------------------------
UPDATED_JSON="$(
python3 - <<'PY'
import json, os

current = json.loads(os.environ["CURRENT_JSON"])
tc_sets = json.loads(os.environ["TC_SETS_JSON"])
prefix = os.environ["PREFIX"]
mode = os.environ.get("SYNC_MODE", "replace")

attrs = current.get("attributes") or {}

def s(x):
    if x is None:
        return None
    if isinstance(x, bool):
        return "true" if x else "false"
    return str(x)

# 1) replace면 해당 scope prefix만 삭제 (tc.<scope>.*)
if mode == "replace":
    attrs = {k: v for k, v in attrs.items() if not k.startswith(prefix)}

# 2) tc_sets를 prefix 기반으로 flatten
# tc_sets: { "privacy": {...}, "tos": {...} }
for set_key, cfg in (tc_sets or {}).items():
    if not isinstance(cfg, dict):
        continue

    attrs[f"{prefix}{set_key}.required"] = s(cfg.get("required", False))

    for field in ("version", "url", "template", "key"):
        v = cfg.get(field)
        if v is None or v == "":
            continue
        attrs[f"{prefix}{set_key}.{field}"] = s(v)

current["attributes"] = attrs
print(json.dumps(current))
PY
)" CURRENT_JSON="${CURRENT_JSON}" TC_SETS_JSON="${TC_SETS_JSON}" PREFIX="${PREFIX}" SYNC_MODE="${SYNC_MODE}"

# Stream JSON into container/pod file (NO docker cp / kubectl cp)
printf '%s' "${UPDATED_JSON}" | kc_write_file "${KC_UPDATED_JSON_PATH}"

# ----------------------------
# Update client-scope using the in-runtime file
# ----------------------------
kc_kcadm update "client-scopes/${SCOPE_ID}" -r "${REALM_ID}" -f "${KC_UPDATED_JSON_PATH}"

echo "Synced attributes under prefix ${PREFIX} (mode=${SYNC_MODE})"
echo "Updated JSON path: ${KC_UPDATED_JSON_PATH} (inside ${KCADM_EXEC_MODE} runtime)"
