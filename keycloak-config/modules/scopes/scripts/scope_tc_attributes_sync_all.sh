#!/usr/bin/env bash
set -Eeuo pipefail

# ===== Required env =====
: "${KCADM_EXEC_MODE:?}"
: "${KCADM_PATH:?}"
: "${KEYCLOAK_URL:?}"
: "${KEYCLOAK_AUTH_REALM:?}"
: "${KEYCLOAK_CLIENT_ID:?}"
: "${KEYCLOAK_CLIENT_SECRET:?}"
: "${TC_SYNC_PAYLOAD_FILE:?}"

# Optional env (docker/kubectl)
KEYCLOAK_CONTAINER_NAME="${KEYCLOAK_CONTAINER_NAME:-}"
KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-}"
KEYCLOAK_POD_SELECTOR="${KEYCLOAK_POD_SELECTOR:-}"

log() { echo "[$(date -Is)] $*" >&2; }
die() { log "FATAL: $*"; exit 1; }

# ===== Isolated HOME to avoid kcadm.config lock =====
KCADM_HOME="$(mktemp -d -t kcadm_home.XXXXXX)"
cleanup() { rm -rf "$KCADM_HOME" || true; }
trap cleanup EXIT

# ===== kcadm exec wrapper =====
kc_exec() {
  case "$KCADM_EXEC_MODE" in
    docker)
      [[ -n "$KEYCLOAK_CONTAINER_NAME" ]] || die "KEYCLOAK_CONTAINER_NAME is required for docker mode"
      docker exec -i "$KEYCLOAK_CONTAINER_NAME" env HOME="$KCADM_HOME" "$KCADM_PATH" "$@"
      ;;
    kubectl)
      [[ -n "$KEYCLOAK_NAMESPACE" ]] || die "KEYCLOAK_NAMESPACE is required for kubectl mode"
      [[ -n "$KEYCLOAK_POD_SELECTOR" ]] || die "KEYCLOAK_POD_SELECTOR is required for kubectl mode"
      POD="$(kubectl -n "$KEYCLOAK_NAMESPACE" get pod -l "$KEYCLOAK_POD_SELECTOR" -o jsonpath='{.items[0].metadata.name}')"
      [[ -n "$POD" ]] || die "No pod found with selector: $KEYCLOAK_POD_SELECTOR"
      kubectl -n "$KEYCLOAK_NAMESPACE" exec -i "$POD" -- env HOME="$KCADM_HOME" "$KCADM_PATH" "$@"
      ;;
    *)
      die "Unknown KCADM_EXEC_MODE=$KCADM_EXEC_MODE (expected docker|kubectl)"
      ;;
  esac
}

# ===== retry wrapper =====
with_retry() {
  local -r max="${1}"; shift
  local -r backoff_ms="${1}"; shift
  local i=1
  while true; do
    if "$@"; then return 0; fi
    rc=$?
    if (( i >= max )); then
      return "$rc"
    fi
    sleep_sec="$(python3 - <<PY
import math
i=${i}
ms=${backoff_ms}
# simple exponential: base * 2^(i-1), capped a bit
val = ms * (2 ** (i-1))
val = min(val, 5000)
print(val/1000.0)
PY
)"
    log "WARN: command failed (rc=$rc), retry $i/$max after ${sleep_sec}s: $*"
    sleep "$sleep_sec"
    i=$((i+1))
  done
}

# ===== Login =====
log "Logging in via kcadm..."
with_retry 5 400 kc_exec config credentials \
  --server "$KEYCLOAK_URL" \
  --realm "$KEYCLOAK_AUTH_REALM" \
  --client "$KEYCLOAK_CLIENT_ID" \
  --secret "$KEYCLOAK_CLIENT_SECRET" >/dev/null

# ===== Read payload =====
PAYLOAD_JSON="$(cat "$TC_SYNC_PAYLOAD_FILE")"

python3 - <<'PY' >/tmp/tc_sync_plan.json
import json, sys

p = json.loads(sys.stdin.read())

def normalize_scope_list(scopes):
  out = []
  for s in scopes:
    tc_sets = s.get("tc_sets") or {}
    # tc_sets is a map: { tc_key: { required, version, title?, url?, template? } }
    out.append({
      "scope_id": s["scope_id"],
      "scope_name": s.get("scope_name",""),
      "scope_key": s.get("scope_key",""),
      "tc_sets": tc_sets
    })
  return out

plan = {
  "realm_id": p["realm_id"],
  "sync_mode": p.get("sync_mode","replace"),
  "allow_delete": bool(p.get("allow_delete", True)),
  "tc_prefix_root": p.get("tc_prefix_root","tc"),
  "dry_run": bool(p.get("dry_run", False)),
  "max_retries": int(p.get("max_retries", 5)),
  "backoff_ms": int(p.get("backoff_ms", 400)),
  "scopes": normalize_scope_list(p.get("client_scopes", [])) + normalize_scope_list(p.get("shared_scopes", []))
}

print(json.dumps(plan, ensure_ascii=False))
PY
<<<"$PAYLOAD_JSON"

PLAN="/tmp/tc_sync_plan.json"
REALM_ID="$(python3 -c 'import json;print(json.load(open("/tmp/tc_sync_plan.json"))["realm_id"])')"

log "Loaded plan: realm=$REALM_ID"

# ===== Helper: get current attributes =====
get_scope_json() {
  local scope_id="$1"
  # return full JSON for the client-scope
  kc_exec get "realms/$REALM_ID/client-scopes/$scope_id"
}

# ===== Helper: update attributes (partial representation) =====
update_scope_attributes() {
  local scope_id="$1"
  local attrs_json_file="$2"
  # Keycloak admin usually accepts partial JSON; if your environment requires full representation,
  # extend python block below to merge more fields (name/protocol/...) from current JSON.
  kc_exec update "realms/$REALM_ID/client-scopes/$scope_id" -f "$attrs_json_file"
}

# ===== Main loop =====
python3 - <<'PY' "$PLAN" > /tmp/tc_scope_list.json
import json, sys
plan = json.load(open(sys.argv[1]))
print(json.dumps(plan["scopes"], ensure_ascii=False))
PY

SCOPES_JSON="$(cat /tmp/tc_scope_list.json)"

# iterate scopes using python to avoid jq dependency
python3 - <<'PY' >/tmp/tc_scope_ids.txt
import json
scopes=json.loads(open("/tmp/tc_scope_list.json").read())
for s in scopes:
  print(s["scope_id"])
PY

SYNC_MODE="$(python3 -c 'import json;print(json.load(open("/tmp/tc_sync_plan.json"))["sync_mode"])')"
ALLOW_DELETE="$(python3 -c 'import json;print("true" if json.load(open("/tmp/tc_sync_plan.json"))["allow_delete"] else "false")')"
TC_PREFIX_ROOT="$(python3 -c 'import json;print(json.load(open("/tmp/tc_sync_plan.json"))["tc_prefix_root"])')"
DRY_RUN="$(python3 -c 'import json;print("true" if json.load(open("/tmp/tc_sync_plan.json"))["dry_run"] else "false")')"
MAX_RETRIES="$(python3 -c 'import json;print(json.load(open("/tmp/tc_sync_plan.json"))["max_retries"])')"
BACKOFF_MS="$(python3 -c 'import json;print(json.load(open("/tmp/tc_sync_plan.json"))["backoff_ms"])')"

log "Sync config: mode=$SYNC_MODE allow_delete=$ALLOW_DELETE prefix=$TC_PREFIX_ROOT dry_run=$DRY_RUN retries=$MAX_RETRIES backoff_ms=$BACKOFF_MS"

# map scope_id -> desired tc_sets
python3 - <<'PY' >/tmp/tc_scope_desired.json
import json
scopes=json.loads(open("/tmp/tc_scope_list.json").read())
m={}
for s in scopes:
  m[s["scope_id"]]={
    "scope_name": s.get("scope_name",""),
    "scope_key": s.get("scope_key",""),
    "tc_sets": s.get("tc_sets",{}) or {}
  }
print(json.dumps(m, ensure_ascii=False))
PY

DESIRED_MAP="/tmp/tc_scope_desired.json"

process_one_scope() {
  local scope_id="$1"
  local current_json tmp_current tmp_update

  tmp_current="$(mktemp -t tc_current.XXXXXX.json)"
  tmp_update="$(mktemp -t tc_update.XXXXXX.json)"

  # fetch current
  if ! with_retry "$MAX_RETRIES" "$BACKOFF_MS" bash -lc "get_scope_json '$scope_id' > '$tmp_current'"; then
    log "ERROR: failed to fetch scope $scope_id"
    return 1
  fi

  # build merged attributes in python
  python3 - <<'PY' "$tmp_current" "$DESIRED_MAP" "$scope_id" "$TC_PREFIX_ROOT" "$SYNC_MODE" "$ALLOW_DELETE" > "$tmp_update"
import json, sys

cur = json.load(open(sys.argv[1]))
desired_map = json.load(open(sys.argv[2]))
scope_id = sys.argv[3]
prefix = sys.argv[4]
mode = sys.argv[5]
allow_delete = (sys.argv[6].lower() == "true")

d = desired_map.get(scope_id)
if not d:
  raise SystemExit(0)

cur_attrs = cur.get("attributes") or {}
tc_sets = d.get("tc_sets") or {}

def tc_attr_key(tc_key, field):
  return f"{prefix}.{tc_key}.{field}"

desired_tc_attrs = {}
for tc_key, tc in tc_sets.items():
  desired_tc_attrs[tc_attr_key(tc_key,"required")] = "true" if tc.get("required") else "false"
  desired_tc_attrs[tc_attr_key(tc_key,"version")] = str(tc.get("version",""))
  title = tc.get("title")
  if title:
    desired_tc_attrs[tc_attr_key(tc_key,"title")] = str(title)
  url = tc.get("url")
  if url:
    desired_tc_attrs[tc_attr_key(tc_key,"url")] = str(url)
  template = tc.get("template")
  if template:
    desired_tc_attrs[tc_attr_key(tc_key,"template")] = str(template)

# keep non-tc attrs as-is
new_attrs = dict(cur_attrs)

if mode == "replace":
  # remove all existing tc.* keys, then add desired
  if allow_delete:
    for k in list(new_attrs.keys()):
      if k.startswith(prefix + "."):
        new_attrs.pop(k, None)
  # if allow_delete is false, we don't remove; we only overwrite/add (safer)
  for k,v in desired_tc_attrs.items():
    new_attrs[k]=v
else:
  # merge: only set/update desired tc keys; do not delete
  for k,v in desired_tc_attrs.items():
    new_attrs[k]=v

out = {"attributes": new_attrs}
print(json.dumps(out, ensure_ascii=False))
PY

  # show summary
  python3 - <<'PY' "$tmp_current" "$tmp_update" "$scope_id"
import json, sys
cur=json.load(open(sys.argv[1]))
upd=json.load(open(sys.argv[2]))
scope_id=sys.argv[3]

cur_a=cur.get("attributes") or {}
upd_a=upd.get("attributes") or {}
# diff counts
added=[k for k in upd_a.keys() if k not in cur_a]
removed=[k for k in cur_a.keys() if k not in upd_a]
changed=[k for k in upd_a.keys() if k in cur_a and cur_a[k]!=upd_a[k]]
print(f"[SCOPE {scope_id}] attr changes: +{len(added)} -{len(removed)} ~{len(changed)}")
PY

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] skip update for scope $scope_id"
    return 0
  fi

  # apply update
  if ! with_retry "$MAX_RETRIES" "$BACKOFF_MS" bash -lc "update_scope_attributes '$scope_id' '$tmp_update' >/dev/null"; then
    log "ERROR: failed to update scope $scope_id"
    return 1
  fi

  log "OK: updated scope $scope_id"
}

rc_all=0
while read -r scope_id; do
  [[ -n "$scope_id" ]] || continue
  if ! process_one_scope "$scope_id"; then
    rc_all=1
  fi
done < /tmp/tc_scope_ids.txt

exit "$rc_all"
