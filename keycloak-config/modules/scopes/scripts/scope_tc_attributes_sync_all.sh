#!/usr/bin/env bash
set -Eeuo pipefail

: "${KCADM_EXEC_MODE:?}"
: "${KCADM_PATH:?}"
: "${KEYCLOAK_URL:?}"
: "${KEYCLOAK_AUTH_REALM:?}"
: "${KEYCLOAK_CLIENT_ID:?}"
: "${KEYCLOAK_CLIENT_SECRET:?}"
: "${TC_SYNC_PAYLOAD_FILE:?}"

KEYCLOAK_CONTAINER_NAME="${KEYCLOAK_CONTAINER_NAME:-}"
KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-}"
KEYCLOAK_POD_SELECTOR="${KEYCLOAK_POD_SELECTOR:-}"

log() { echo "[$(date -Is)] $*" >&2; }
die() { log "FATAL: $*"; exit 1; }

# ---- Isolated HOME (kcadm.config lock 방지)
KCADM_HOME="$(mktemp -d -t kcadm_home.XXXXXX)"
trap 'rm -rf "$KCADM_HOME" || true' EXIT

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

with_retry() {
  local max="$1"; shift
  local backoff_ms="$1"; shift
  local i=1 rc=0
  while true; do
    if "$@"; then return 0; fi
    rc=$?
    if (( i >= max )); then return "$rc"; fi
    local sleep_sec
    sleep_sec="$(python3 - <<PY
import math
i=${i}
ms=${backoff_ms}
val = ms * (2 ** (i-1))
val = min(val, 5000)
print(val/1000.0)
PY
)"
    log "WARN: failed rc=$rc retry $i/$max after ${sleep_sec}s: $*"
    sleep "$sleep_sec"
    i=$((i+1))
  done
}

# ---- Load plan
PLAN="$(mktemp -t tc_plan.XXXXXX.json)"
python3 - <<'PY' >"$PLAN"
import json
p=json.load(open("${TC_SYNC_PAYLOAD_FILE}","r",encoding="utf-8"))

plan={
  "realm_id": p["realm_id"],
  "sync_mode": p.get("sync_mode","replace"),
  "allow_delete": bool(p.get("allow_delete", True)),
  "tc_prefix_root": p.get("tc_prefix_root","tc"),
  "dry_run": bool(p.get("dry_run", False)),
  "max_retries": int(p.get("max_retries", 5)),
  "backoff_ms": int(p.get("backoff_ms", 400)),
  "scopes": []
}

def add(scopes):
  for s in scopes or []:
    plan["scopes"].append({
      "scope_id": s["scope_id"],
      "scope_name": s.get("scope_name",""),
      "scope_key": s.get("scope_key",""),
      "tc_sets": s.get("tc_sets") or {}
    })

add(p.get("client_scopes"))
add(p.get("shared_scopes"))

print(json.dumps(plan, ensure_ascii=False))
PY

REALM_ID="$(python3 -c 'import json;print(json.load(open("'"$PLAN"'"))["realm_id"])')"
SYNC_MODE="$(python3 -c 'import json;print(json.load(open("'"$PLAN"'"))["sync_mode"])')"
ALLOW_DELETE="$(python3 -c 'import json;print("true" if json.load(open("'"$PLAN"'"))["allow_delete"] else "false")')"
TC_PREFIX_ROOT="$(python3 -c 'import json;print(json.load(open("'"$PLAN"'"))["tc_prefix_root"])')"
DRY_RUN="$(python3 -c 'import json;print("true" if json.load(open("'"$PLAN"'"))["dry_run"] else "false")')"
MAX_RETRIES="$(python3 -c 'import json;print(json.load(open("'"$PLAN"'"))["max_retries"])')"
BACKOFF_MS="$(python3 -c 'import json;print(json.load(open("'"$PLAN"'"))["backoff_ms"])')"

log "Plan: realm=$REALM_ID mode=$SYNC_MODE allow_delete=$ALLOW_DELETE prefix=$TC_PREFIX_ROOT dry_run=$DRY_RUN retries=$MAX_RETRIES backoff_ms=$BACKOFF_MS"

# ---- Login
log "Login via kcadm..."
with_retry 5 400 kc_exec config credentials \
  --server "$KEYCLOAK_URL" \
  --realm "$KEYCLOAK_AUTH_REALM" \
  --client "$KEYCLOAK_CLIENT_ID" \
  --secret "$KEYCLOAK_CLIENT_SECRET" >/dev/null

# ---- Helpers
get_scope_json() {
  local scope_id="$1"
  kc_exec get "realms/$REALM_ID/client-scopes/$scope_id"
}
update_scope_attributes() {
  local scope_id="$1"
  local file="$2"
  kc_exec update "realms/$REALM_ID/client-scopes/$scope_id" -f "$file"
}

# ---- Build desired map
DESIRED="$(mktemp -t tc_desired.XXXXXX.json)"
python3 - <<'PY' >"$DESIRED"
import json
plan=json.load(open("'"$PLAN"'"))
m={}
for s in plan["scopes"]:
  m[s["scope_id"]]={
    "scope_key": s.get("scope_key",""),
    "scope_name": s.get("scope_name",""),
    "tc_sets": s.get("tc_sets") or {}
  }
print(json.dumps(m, ensure_ascii=False))
PY

# ---- Iterate scope ids
IDS="$(mktemp -t tc_ids.XXXXXX.txt)"
python3 - <<'PY' >"$IDS"
import json
plan=json.load(open("'"$PLAN"'"))
for s in plan["scopes"]:
  print(s["scope_id"])
PY

process_one_scope() {
  local scope_id="$1"
  local cur upd
  cur="$(mktemp -t tc_cur.XXXXXX.json)"
  upd="$(mktemp -t tc_upd.XXXXXX.json)"

  if ! with_retry "$MAX_RETRIES" "$BACKOFF_MS" bash -lc "get_scope_json '$scope_id' > '$cur'"; then
    log "ERROR: fetch failed scope_id=$scope_id"
    return 1
  fi

  python3 - <<'PY' "$cur" "$DESIRED" "$scope_id" "$TC_PREFIX_ROOT" "$SYNC_MODE" "$ALLOW_DELETE" >"$upd"
import json, sys
cur=json.load(open(sys.argv[1]))
desired=json.load(open(sys.argv[2]))
scope_id=sys.argv[3]
prefix=sys.argv[4]
mode=sys.argv[5]
allow_delete=(sys.argv[6].lower()=="true")

d=desired.get(scope_id)
if not d:
  print(json.dumps({"attributes": cur.get("attributes") or {}}, ensure_ascii=False))
  raise SystemExit(0)

cur_attrs=cur.get("attributes") or {}
tc_sets=d.get("tc_sets") or {}

def k(tc_key, field): return f"{prefix}.{tc_key}.{field}"

desired_tc={}
for tc_key, tc in tc_sets.items():
  desired_tc[k(tc_key,"required")] = "true" if tc.get("required") else "false"
  desired_tc[k(tc_key,"version")]  = str(tc.get("version",""))
  if tc.get("title"):    desired_tc[k(tc_key,"title")]    = str(tc["title"])
  if tc.get("url"):      desired_tc[k(tc_key,"url")]      = str(tc["url"])
  if tc.get("template"): desired_tc[k(tc_key,"template")] = str(tc["template"])

new_attrs=dict(cur_attrs)

if mode=="replace":
  if allow_delete:
    for kk in list(new_attrs.keys()):
      if kk.startswith(prefix+"."):
        new_attrs.pop(kk, None)
  for kk,vv in desired_tc.items():
    new_attrs[kk]=vv
else:
  for kk,vv in desired_tc.items():
    new_attrs[kk]=vv

print(json.dumps({"attributes": new_attrs}, ensure_ascii=False))
PY

  python3 - <<'PY' "$cur" "$upd" "$scope_id"
import json, sys
cur=json.load(open(sys.argv[1]))
upd=json.load(open(sys.argv[2]))
sid=sys.argv[3]
a=cur.get("attributes") or {}
b=upd.get("attributes") or {}
added=[k for k in b if k not in a]
removed=[k for k in a if k not in b]
changed=[k for k in b if k in a and a[k]!=b[k]]
print(f"[SCOPE {sid}] +{len(added)} -{len(removed)} ~{len(changed)}")
PY

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] skip update scope_id=$scope_id"
    return 0
  fi

  if ! with_retry "$MAX_RETRIES" "$BACKOFF_MS" bash -lc "update_scope_attributes '$scope_id' '$upd' >/dev/null"; then
    log "ERROR: update failed scope_id=$scope_id"
    return 1
  fi

  log "OK: updated scope_id=$scope_id"
}

rc=0
while read -r sid; do
  [[ -n "$sid" ]] || continue
  process_one_scope "$sid" || rc=1
done <"$IDS"

exit "$rc"
