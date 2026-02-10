#!/usr/bin/env bash
set -Eeuo pipefail

# Terraform 콘솔 유실 방지: stdout도 stderr로
exec 1>&2

trap 'rc=$?;
  echo "[FATAL] rc=$rc at ${BASH_SOURCE##*/}:${LINENO} :: ${BASH_COMMAND}" >&2
  exit "$rc"
' ERR

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
: "${KCADM_PATH:=/opt/bitnami/keycloak/bin/kcadm.sh}"  # ✅ must be executable, not a dir

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
KC_UPDATED_JSON_PATH="${KC_UPDATED_JSON_PATH:-${KC_TMP_DIR}/kc-scope-update-${REALM_ID}-${SCOPE_NAME}.json}"

KEYTOOL_BIN="${KEYTOOL_BIN:-/opt/bitnami/java/bin/keytool}"
KCADM_HOME_DIR="${KCADM_HOME_DIR:-/tmp/kcadm-home-${REALM_ID}-${SCOPE_NAME}-${SCOPE_KEY}}"

DEBUG="${DEBUG:-false}"

log() { echo "[$(date -Iseconds)] $*" >&2; }

dbg() {
  if [ "${DEBUG:-false}" = "true" ]; then
    log "[DEBUG] $*"
  fi
  return 0
}

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
      pod="$(kubectl -n "${KEYCLOAK_NAMESPACE}" get pod -l "${KEYCLOAK_POD_SELECTOR}" -o jsonpath='{.items[0].metadata.name}')"
      [ -n "${pod}" ] || { echo "No Keycloak pod found" >&2; exit 1; }
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
  # HOME 디렉토리는 여기서 확실히 만들어둠 (컨테이너 내부에서)
  "${KC_EXEC[@]}" /bin/sh -lc "set -e; HOME='${KCADM_HOME_DIR}'; mkdir -p \"\$HOME\""
  # kcadm은 쉘 없이 argv 그대로 실행 (가장 안정적)
  "${KC_EXEC[@]}" env HOME="${KCADM_HOME_DIR}" "${KCADM_PATH}" "$@"
}

kc_write_file() {
  path="$1"
  "${KC_EXEC_I[@]}" /bin/sh -lc "set -e; HOME='${KCADM_HOME_DIR}'; mkdir -p \"\$HOME\"; mkdir -p \"$(dirname "$path")\"; cat > \"$path\""
}

# ✅ kcadm 결과를 stdout+stderr 통합 캡처 + rc/empty 검증
kc_kcadm_capture() {
  # usage: kc_kcadm_capture <varname> <kcadm args...>
  out_var="$1"
  shift

  set +e
  out="$(kc_kcadm "$@" 2>&1)"
  rc=$?
  set -e

  # ✅ eval 제거: 안전하게 변수에 그대로 대입
  printf -v "$out_var" '%s' "$out"

  if [ $rc -ne 0 ]; then
    echo "[ERROR] kcadm failed (rc=$rc): kcadm $*" >&2
    echo "[ERROR] output(begin)" >&2
    echo "$out" >&2
    echo "[ERROR] output(end)" >&2
    return $rc
  fi

  if [ -z "$out" ]; then
    echo "[ERROR] kcadm returned empty output: kcadm $*" >&2
    return 1
  fi

  return 0
}

kc_init_exec

log "[BOOT] start mode=${KCADM_EXEC_MODE} realm=${REALM_ID} scope=${SCOPE_NAME}"
dbg "KCADM_PATH=${KCADM_PATH}"
dbg "KCADM_HOME_DIR=${KCADM_HOME_DIR}"

# =========================
# Preflight: ensure kcadm exists
# =========================
kc_sh "test -x '${KCADM_PATH}' || { echo 'ERROR: KCADM_PATH not executable: ${KCADM_PATH}' >&2; exit 1; }"

# =========================
# TLS truststore setup
# =========================
if [ "${KEYCLOAK_TLS_MODE}" = "truststore" ]; then
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
elif [ "${KEYCLOAK_TLS_MODE}" = "off" ]; then
  :
else
  echo "Unsupported KEYCLOAK_TLS_MODE: ${KEYCLOAK_TLS_MODE} (use truststore|off)" >&2
  exit 1
fi

# =========================
# kcadm login
# =========================
kc_kcadm_capture KC_LOGIN_OUT config credentials \
  --server "${KEYCLOAK_URL}" \
  --realm "${KEYCLOAK_AUTH_REALM}" \
  --client "${KEYCLOAK_CLIENT_ID}" \
  --secret "${KEYCLOAK_CLIENT_SECRET}"
dbg "kcadm login ok"

# =========================
# Resolve/validate SCOPE_ID by SCOPE_NAME (protect against recreate)
# =========================
dbg "Resolving scope id by name: ${SCOPE_NAME}"
kc_kcadm_capture RAW_SCOPES_JSON get client-scopes -r "${REALM_ID}" -q "name=${SCOPE_NAME}"

dbg "RAW_SCOPES_JSON(head 300)=$(printf '%s' "$RAW_SCOPES_JSON" | head -c 300)"
dbg "SCOPE_NAME=${SCOPE_NAME} REALM_ID=${REALM_ID}"


FOUND_ID="$(
  printf '%s' "$RAW_SCOPES_JSON" |
  python3 -c 'import sys, json, os
expected = os.environ["SCOPE_NAME"]
s = sys.stdin.read().strip()
if not s or s[0] not in "[{":
  raise SystemExit(f"ERROR: expected JSON from kcadm but got:\n{s[:800]}")
obj = json.loads(s)

if not isinstance(obj, list):
  raise SystemExit(f"ERROR: expected list from kcadm but got type={type(obj)} head:\n{s[:800]}")

matches = [x for x in obj if isinstance(x, dict) and x.get("name") == expected]
if len(matches) == 1:
  print(matches[0].get("id","") or "")
elif len(matches) == 0:
  # 디버그: 상위 몇 개 이름을 보여줘서 원인 파악 쉽게
  names = [x.get("name") for x in obj[:10] if isinstance(x, dict)]
  raise SystemExit(f"ERROR: no client-scope matched name={expected!r}. First names={names!r}")
else:
  ids = [m.get("id") for m in matches]
  raise SystemExit(f"ERROR: multiple client-scopes matched name={expected!r}. ids={ids!r}")
' SCOPE_NAME="${SCOPE_NAME}"
)"


if [ -z "${FOUND_ID}" ]; then
  echo "ERROR: client-scope not found by name='${SCOPE_NAME}' in realm='${REALM_ID}'" >&2
  echo "kcadm returned: $RAW_SCOPES_JSON" >&2
  exit 1
fi

if [ "${FOUND_ID}" != "${SCOPE_ID}" ]; then
  log "[WARN] SCOPE_ID mismatch. Using id resolved by name."
  log "       env SCOPE_ID=${SCOPE_ID}"
  log "       resolved=${FOUND_ID} (name=${SCOPE_NAME})"
  SCOPE_ID="${FOUND_ID}"
fi

# =========================
# Fetch current client-scope JSON
# =========================
kc_kcadm_capture CURRENT_JSON get "client-scopes/${SCOPE_ID}" -r "${REALM_ID}"

# verify name
printf '%s' "$CURRENT_JSON" | python3 -c 'import sys, json, os
cur=json.loads(sys.stdin.read())
expected=os.environ["SCOPE_NAME"]
name=cur.get("name")
if name!=expected:
  raise SystemExit(f"ERROR: fetched scope name mismatch: got={name!r} expected={expected!r}")
' SCOPE_NAME="${SCOPE_NAME}"

dbg "Building updated payload (mode=${SYNC_MODE})"
dbg "TC_SETS_JSON_SHA256=$(printf '%s' "${TC_SETS_JSON}" | sha256sum | awk '{print $1}')"

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

payload = {}
for k in ("id", "name", "protocol", "description", "consentScreenText", "includeInTokenScope"):
    if k in current and current[k] is not None:
        payload[k] = current[k]

attrs = current.get("attributes") or {}
if not isinstance(attrs, dict):
    attrs = {}

if mode == "replace":
    attrs = {k: v for k, v in attrs.items() if not str(k).startswith(prefix)}
    attrs.pop("tc.terms", None)

terms = []
for term_key, cfg in (tc_sets or {}).items():
    if not isinstance(cfg, dict):
        continue
    title = cfg.get("title") or term_key
    required = bool(cfg.get("required", False))
    version = cfg.get("version")
    if not version:
        raise SystemExit(f"ERROR: term.version missing for key={term_key}")
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
print(json.dumps(payload, ensure_ascii=False))
PY

python3 -m json.tool "${TMP_JSON}" >/dev/null || {
  echo "ERROR: invalid json generated on host" >&2
  sed -n '1,5p' "${TMP_JSON}" >&2
  tail -n 5 "${TMP_JSON}" >&2
  exit 1
}

cat "${TMP_JSON}" | kc_write_file "${KC_UPDATED_JSON_PATH}"
kc_sh "test -s '${KC_UPDATED_JSON_PATH}' || { echo 'ERROR: updated json file empty: ${KC_UPDATED_JSON_PATH}' >&2; exit 1; }"

# =========================
# Update client-scope with minimal representation
# =========================
log "Updating client-scope: realm=${REALM_ID} id=${SCOPE_ID} name=${SCOPE_NAME} key=${SCOPE_KEY}"
kc_kcadm_capture UPDATE_OUT update "client-scopes/${SCOPE_ID}" -r "${REALM_ID}" -f "${KC_UPDATED_JSON_PATH}"

# =========================
# Verify update applied (read-back)
# =========================
kc_kcadm_capture UPDATED_JSON get "client-scopes/${SCOPE_ID}" -r "${REALM_ID}"

# ✅ FIX: 파이프 + python3 - + heredoc 충돌 제거 (python3 -c 사용)
UPDATED_TC_TERMS="$(
  printf '%s' "$UPDATED_JSON" |
  python3 -c 'import sys, json
s = sys.stdin.read().strip()
if not s or s[0] not in "{[":
  raise SystemExit(f"ERROR: expected JSON from kcadm but got:\n{s[:800]}")
cur = json.loads(s)
attrs = cur.get("attributes") or {}
print(attrs.get("tc.terms","") or "")
'
)"

if [ -z "${UPDATED_TC_TERMS}" ]; then
  echo "ERROR: tc.terms missing after update (update may have failed or ignored)" >&2
  exit 1
fi

log "[OK] tc.terms updated"
dbg "tc.terms(first 200 chars)=$(echo "${UPDATED_TC_TERMS}" | head -c 200)"

echo "Synced terms to attribute tc.terms (mode=${SYNC_MODE})"
echo "Legacy prefix cleanup applied: ${PREFIX} (mode=replace only)"
echo "Scope: id=${SCOPE_ID}, key=${SCOPE_KEY}, name=${SCOPE_NAME}"
echo "Updated JSON path: ${KC_UPDATED_JSON_PATH} (inside ${KCADM_EXEC_MODE} runtime)"
