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

"${KCADM_BASE[@]}" config credentials \
  --server "${KEYCLOAK_URL}" \
  --realm "${KEYCLOAK_AUTH_REALM}" \
  --client "${KEYCLOAK_CLIENT_ID}" \
  --secret "${KEYCLOAK_CLIENT_SECRET}"

CURRENT_JSON="$("${KCADM_BASE[@]}" get "client-scopes/${SCOPE_ID}" -r "${REALM_ID}")"

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

"${KCADM_BASE[@]}" update "client-scopes/${SCOPE_ID}" -r "${REALM_ID}" -f "${TMP}"
echo "Synced attributes under prefix ${PREFIX} (mode=${SYNC_MODE})"
