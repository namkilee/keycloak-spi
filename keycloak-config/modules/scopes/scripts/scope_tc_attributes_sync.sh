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
: "${SCOPE_NAME:?}"              # ✅ actual Keycloak client-scope name
: "${TC_SETS_JSON:?}"

# =========================
# Optional envs
# =========================
TC_PREFIX_ROOT="${TC_PREFIX_ROOT:-tc}"
SYNC_MODE="${SYNC_MODE:-replace}"   # replace = tc.<scopeName>.* 삭제 후 재작성

# legacy prefix cleanup 기준은 "실제 scope name"으로!
PREFIX="${TC_PREFIX_ROOT}.${SCOPE_NAME}."

# TLS truststore mode:
# - truststore: create/import CA cert into JKS and configure kcadm truststore (recommended)
# - off: do nothing (use if http:// or publicly trusted cert chain)
KEYCLOAK_TLS_MODE="${KEYCLOAK_TLS_MODE:-truststore}"

# IMPORTANT: must be a path INSIDE container/pod because kcadm runs there
KEYCLOAK_CA_CERT_PEM="${KEYCLOAK_CA_CERT_PEM:-/certs/tls.crt}"

KCADM_TRUSTSTORE_DIR="${KCADM_TRUSTSTORE_DIR:-/tmp}"
KCADM_TRUSTSTORE_FILE="${KCADM_TRUSTSTORE_FILE:-${KCADM_TRUSTSTORE_DIR}/kcadm-truststore.jks}"
KCADM_TRUSTSTORE_PASS="${KCADM_TRUSTSTORE_PASS:-keycloak}"
KCADM_TRUSTSTORE_ALIAS="${KCADM_TRUSTSTORE_ALIAS:-keycloak-ca}"

KC_TMP_DIR="${KC_TMP_DIR:-/tmp}"
KC_UPDATED_JSON_PATH="${KC_UPDATED_JSON_PATH:-${KC_TMP_DIR}/kc-scope-update-${SCOPE_ID}.json}"

# Bitnami Keycloak image: keytool exists here but PATH may not include it in /bin/sh non-login shells
KEYTOOL_BIN="${KEYTOOL_BIN:-/opt/bitnami/java/bin/keytool}"

# IMPORTANT:
# kcadm writes config to $HOME/.keycloak/kcadm.config and uses a lock.
# Terraform may run local-exec in parallel -> lock conflict if HOME is shared.
# So we isolate HOME per execution by default.
KCADM_HOME_DIR="${KCADM_HOME_DIR:-/tmp/kcadm-home-${REALM_ID}-${SCOPE_ID}-${SCOPE_KEY}}"

# =========================
# Common exec base (docker/kubectl)
# =========================
kc_init_exec() {
  case "${KCADM_EXEC_MODE}" in
    docker)
      : "${KEYCLOAK_CONTAINER_NAME:?}"
      KC_EXEC=(docker exec "${KEYCLOAK_CONTAINER_NAME}")
      KC_EXEC_I=(docker exec -i "${KEYCLOAK_CONTAINER_NAME}")   # stdin 전달용
      ;;
    kubectl)
      : "${KEYCLOAK_NAMESPACE:?}"
      : "${KEYCLOAK_POD_SELECTOR:?}"
      local pod
      pod="$(kubectl -n "${KEYCLOAK_NAMESPACE}" get pod -l "${KEYCLOAK_POD_SELECTOR}" -o jsonpath='{.items[0].metadata.name}')"
      [[ -n "${pod}" ]] || { echo "No Keycloak pod found" >&2; exit 1; }
      KC_EXEC=(kubectl -n "${KEYCLOAK_NAMESPACE}" exec "${pod}" --)
      KC_EXEC_I=(kubectl -n "${KEYCLOAK_NAMESPACE}" exec -i "${pod}" --)  # stdin 전달용
      ;;
    *)
      echo "Unsupported KCADM_EXEC_MODE: ${KCADM_EXEC_MODE}" >&2
      exit 1
      ;;
  esac
}

# Run shell inside container/pod with isolated HOME
kc_sh() {
  "${KC_EXEC[@]}" /bin/sh -lc "set -e; HOME='${KCADM_HOME_DIR}'; mkdir -p \"\$HOME\"; $*"
}

# Run kcadm inside container/pod with isolated HOME (robust argv passing)
kc_kcadm() {
  "${KC_EXEC[@]}" /bin/sh -lc '
    set -e
    HOME="$1"
    shift
    mkdir -p "$HOME"
    exec "$@"
  ' -- "${KCADM_HOME_DIR}" "${KCADM_PATH}" "$@"
}

# Write a file inside container/pod using stdin (no docker cp / kubectl cp)
kc_write_file() {
  local path="$1"
  "${KC_EXEC_I[@]}" /bin/sh -lc "set -e; HOME='${KCADM_HOME_DIR}'; mkdir -p \"\$HOME\"; mkdir -p \"$(dirname "$path")\" && cat > \"$path\""
}

kc_init_exec

# =========================
# TLS truststore setup
# =========================
if [[ "${KEYCLOAK_TLS_MODE}" == "truststore" ]]; then
  if [[ -z "${KEYCLOAK_CA_CERT_PEM}" ]]; then
    cat >&2 <<EOF
ERROR: KEYCLOAK_TLS_MODE=truststore requires KEYCLOAK_CA_CERT_PEM (path inside container/pod).
Because kcadm runs inside ${KCADM_EXEC_MODE}, this must exist INSIDE that runtime.
EOF
    exit 1
  fi

  kc_sh "
    test -f '${KEYCLOAK_CA_CERT_PEM}' || { echo 'ERROR: cert not found: ${KEYCLOAK_CA_CERT_PEM}' >&2; exit 1; }

    if [ ! -x '${KEYTOOL_BIN}' ]; then
      echo 'ERROR: keytool not executable at ${KEYTOOL_BIN}' >&2
      echo 'HINT: set KEYTOOL_BIN to the actual path inside container/pod' >&2
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
# Fetch current client-scope JSON (for existing attributes)
# =========================
CURRENT_JSON="$(kc_kcadm get "client-scopes/${SCOPE_ID}" -r "${REALM_ID}")"
[[ -n "${CURRENT_JSON}" ]] || { echo "ERROR: CURRENT_JSON is empty (scope not found?)" >&2; exit 1; }

# =========================
# Build UPDATED payload:
# - DO NOT PUT whole representation back (can fail with parse/unknown_error)
# - PUT only {"attributes": {...}} minimal payload
# =========================
UPDATED_JSON="$(
  CURRENT_JSON="${CURRENT_JSON}" \
  TC_SETS_JSON="${TC_SETS_JSON}" \
  PREFIX="${PREFIX}" \
  SYNC_MODE="${SYNC_MODE}" \
  python3 - <<'PY'
import json, os

current = json.loads(os.environ["CURRENT_JSON"])
tc_sets = json.loads(os.environ["TC_SETS_JSON"])
prefix = os.environ["PREFIX"]
mode = os.environ.get("SYNC_MODE", "replace")

attrs = current.get("attributes") or {}

def to_list_str(v):
    if v is None:
        return None
    if isinstance(v, list):
        return [str(x) for x in v]
    return [str(v)]

# normalize existing attrs to List[str] (safer for update)
attrs = {k: to_list_str(v) for k, v in attrs.items() if to_list_str(v) is not None}

if mode == "replace":
    # remove legacy flatten keys for this scope (tc.<scopeName>.*)
    attrs = {k: v for k, v in attrs.items() if not k.startswith(prefix)}
    # remove current tc.terms to rewrite it clean
    attrs.pop("tc.terms", None)

# build terms list from tc_sets
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

# Keycloak attributes values: prefer List<String>
attrs["tc.terms"] = [json.dumps(terms, ensure_ascii=False)]

payload = {"attributes": attrs}
print(json.dumps(payload))
PY
)"

[[ -n "${UPDATED_JSON}" ]] || { echo "ERROR: UPDATED_JSON is empty" >&2; exit 1; }

printf '%s' "${UPDATED_JSON}" | kc_write_file "${KC_UPDATED_JSON_PATH}"

# =========================
# Validate JSON file inside container/pod before update (fast failure)
# =========================
kc_sh "python3 -m json.tool '${KC_UPDATED_JSON_PATH}' >/dev/null || { echo 'ERROR: invalid json file'; cat '${KC_UPDATED_JSON_PATH}'; exit 1; }"
kc_sh "test -s '${KC_UPDATED_JSON_PATH}' || { echo 'ERROR: updated json file is empty: ${KC_UPDATED_JSON_PATH}' >&2; exit 1; }"

# =========================
# Update only attributes (minimal payload)
# =========================
kc_kcadm update "client-scopes/${SCOPE_ID}" -r "${REALM_ID}" -f "${KC_UPDATED_JSON_PATH}"

echo "Synced terms to attribute tc.terms (mode=${SYNC_MODE})"
echo "Legacy prefix cleanup applied: ${PREFIX} (mode=replace only)"
echo "Scope: id=${SCOPE_ID}, key=${SCOPE_KEY}, name=${SCOPE_NAME}"
echo "KCADM_HOME_DIR (isolated): ${KCADM_HOME_DIR}"
echo "Updated JSON path: ${KC_UPDATED_JSON_PATH} (inside ${KCADM_EXEC_MODE} runtime)"
