#!/usr/bin/env bash
set -euo pipefail

: "${KCADM_PATH:?}"
: "${KCADM_EXEC_MODE:?}"
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

# ---- TLS / truststore settings (NEW) ----
# truststore (default): create/import CA cert into JKS and configure kcadm truststore
# insecure: disable TLS validation (local test only)
KEYCLOAK_TLS_MODE="${KEYCLOAK_TLS_MODE:-truststore}"

# When KEYCLOAK_TLS_MODE=truststore, you must provide a PEM cert that the Java client can trust.
# IMPORTANT: Because kcadm is executed INSIDE container/pod (docker/kubectl mode),
# this path must be accessible INSIDE that container/pod.
KEYCLOAK_CA_CERT_PEM="${KEYCLOAK_CA_CERT_PEM:-}"

KCADM_TRUSTSTORE_DIR="${KCADM_TRUSTSTORE_DIR:-/tmp}"
KCADM_TRUSTSTORE_FILE="${KCADM_TRUSTSTORE_FILE:-${KCADM_TRUSTSTORE_DIR}/kcadm-truststore.jks}"
KCADM_TRUSTSTORE_PASS="${KCADM_TRUSTSTORE_PASS:-changeit}"
KCADM_TRUSTSTORE_ALIAS="${KCADM_TRUSTSTORE_ALIAS:-keycloak-ca}"
# ----------------------------------------

case "${KCADM_EXEC_MODE}" in
  docker)
    : "${KEYCLOAK_CONTAINER_NAME:?}"
    KCADM_BASE=(docker exec "${KEYCLOAK_CONTAINER_NAME}" "${KCADM_PATH}")
    ;;
  kubectl)
    : "${KEYCLOAK_NAMESPACE:?}"
    : "${KEYCLOAK_POD_SELECTOR:?}"
    POD="$(kubectl -n "${KEYCLOAK_NAMESPACE}" get pod -l "${KEYCLOAK_POD_SELECTOR}" -o jsonpath='{.items[0].metadata.name}')"
    [ -n "${POD}" ] || { echo "No Keycloak pod found" >&2; exit 1; }
    KCADM_BASE=(kubectl -n "${KEYCLOAK_NAMESPACE}" exec "$POD" -- "${KCADM_PATH}")
    ;;
  *)
    echo "Unsupported KCADM_EXEC_MODE: ${KCADM_EXEC_MODE}" >&2
    exit 1
    ;;
esac

# ---- configure TLS trust (NEW) ----
case "${KEYCLOAK_TLS_MODE}" in
  truststore)
    if [[ -z "${KEYCLOAK_CA_CERT_PEM}" ]]; then
      cat >&2 <<EOF
ERROR: KEYCLOAK_TLS_MODE=truststore but KEYCLOAK_CA_CERT_PEM is empty.
Provide a PEM certificate that should be trusted by the Java client.

Because kcadm is executed inside ${KCADM_EXEC_MODE}, the file path must exist inside that container/pod.
EOF
      exit 1
    fi

    # Create truststore and import cert INSIDE the container/pod
    # (kcadm runs there, so its JVM trust must be configured there too)
    "${KCADM_BASE[@]}" /bin/sh -lc "
      set -e
      if [ ! -f '${KEYCLOAK_CA_CERT_PEM}' ]; then
        echo 'ERROR: CA cert not found inside runtime: ${KEYCLOAK_CA_CERT_PEM}' >&2
        exit 1
      fi

      mkdir -p '${KCADM_TRUSTSTORE_DIR}'

      # If alias already exists, keep it. Otherwise (re)create the truststore.
      if [ -f '${KCADM_TRUSTSTORE_FILE}' ] && keytool -list -keystore '${KCADM_TRUSTSTORE_FILE}' -storepass '${KCADM_TRUSTSTORE_PASS}' -alias '${KCADM_TRUSTSTORE_ALIAS}' >/dev/null 2>&1; then
        echo '[OK] truststore already has alias ${KCADM_TRUSTSTORE_ALIAS}'
      else
        rm -f '${KCADM_TRUSTSTORE_FILE}'
        keytool -importcert -noprompt \
          -alias '${KCADM_TRUSTSTORE_ALIAS}' \
          -file '${KEYCLOAK_CA_CERT_PEM}' \
          -keystore '${KCADM_TRUSTSTORE_FILE}' \
          -storepass '${KCADM_TRUSTSTORE_PASS}'
      fi
    "

    # Tell kcadm to use that truststore
    "${KCADM_BASE[@]}" config truststore --trustpass "${KCADM_TRUSTSTORE_PASS}" "${KCADM_TRUSTSTORE_FILE}"
    ;;

  insecure)
    # Local-test only: this turns off TLS validation for kcadm by setting JAVA_OPTS.
    # Note: This affects ONLY the current invocation environment inside container/pod.
    # We pass JAVA_OPTS inline when calling kcadm below by prefixing the command.
    # We'll handle it by wrapping KCADM_BASE calls for credential config.
    ;;
  *)
    echo "Unsupported KEYCLOAK_TLS_MODE: ${KEYCLOAK_TLS_MODE} (use truststore|insecure)" >&2
    exit 1
    ;;
esac
# ------------------------------------

# Helper to run kcadm with optional insecure JAVA_OPTS
kcadm_run() {
  if [[ "${KEYCLOAK_TLS_MODE}" == "insecure" ]]; then
    # disable trust checks (NOT recommended outside local testing)
    "${KCADM_BASE[@]}" /bin/sh -lc "JAVA_OPTS='-Dcom.sun.net.ssl.checkRevocation=false -Djavax.net.ssl.trustStoreType=JKS -Djava.security.egd=file:/dev/./urandom -Dsun.security.ssl.allowUnsafeRenegotiation=true -Dcom.sun.security.enableAIAcaIssuers=false -Djavax.net.ssl.trustStore=/dev/null' ${KCADM_PATH} $*"
  else
    "${KCADM_BASE[@]}" "$@"
  fi
}

# Login
kcadm_run config credentials \
  --server "${KEYCLOAK_URL}" \
  --realm "${KEYCLOAK_AUTH_REALM}" \
  --client "${KEYCLOAK_CLIENT_ID}" \
  --secret "${KEYCLOAK_CLIENT_SECRET}"

CURRENT_JSON="$(kcadm_run get "client-scopes/${SCOPE_ID}" -r "${REALM_ID}")"

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
    attrs = {k:v for k,v in attrs.items() if not k.startswith(prefix)}

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

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
printf '%s' "${UPDATED_JSON}" > "${TMP}"

kcadm_run update "client-scopes/${SCOPE_ID}" -r "${REALM_ID}" -f "${TMP}"
echo "Synced attributes under prefix ${PREFIX} (mode=${SYNC_MODE})"
