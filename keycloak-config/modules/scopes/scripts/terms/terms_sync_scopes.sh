#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/kc_kcadm.sh"

need_cmd jq
: "${TERMS_SYNC_PAYLOAD_FILE:?}"

# ---------------------------
# Debug / behavior options
# ---------------------------
JQ_DEBUG="${JQ_DEBUG:-0}"
DUMP_DIR="${DUMP_DIR:-.terms_sync_debug}"
LAST_STEP="init"

# 상세 diff 로그 출력 개수 제한
DIFF_LOG_LIMIT="${DIFF_LOG_LIMIT:-200}"

ATTR_TERMS_CONFIG="terms_config"
ATTR_TERMS_PRIORITY="terms_priority"

ensure_dump_dir() { mkdir -p "$DUMP_DIR"; }

dump_file_copy() {
  local src="$1" name="$2"
  [[ -f "$src" ]] || return 0
  ensure_dump_dir
  cp -f "$src" "$DUMP_DIR/$name" 2>/dev/null || true
}

dump_json_pretty_from_file() {
  local src="$1" name="$2"
  [[ -f "$src" ]] || return 0
  ensure_dump_dir
  jq '.' "$src" > "$DUMP_DIR/$name" 2>/dev/null || cp -f "$src" "$DUMP_DIR/$name.raw" 2>/dev/null || true
}

dump_json_pretty_from_text() {
  local name="$1" json="$2"
  ensure_dump_dir
  printf '%s\n' "$json" | jq '.' > "$DUMP_DIR/$name" 2>/dev/null || printf '%s\n' "$json" > "$DUMP_DIR/$name.raw" 2>/dev/null || true
}

on_err() {
  local exit_code=$?
  echo "[FATAL] failed (exit=$exit_code) step=$LAST_STEP line=${BASH_LINENO[0]} cmd=${BASH_COMMAND}" >&2
  echo "[FATAL] dump dir: $DUMP_DIR" >&2
  dump_file_copy "$TERMS_SYNC_PAYLOAD_FILE" "payload.json.raw"
  dump_json_pretty_from_file "$TERMS_SYNC_PAYLOAD_FILE" "payload.json"
  exit "$exit_code"
}
trap on_err ERR

run_jq_file() {
  local step="$1" program="$2" in_file="$3"; shift 3
  local jq_args=("$@")
  LAST_STEP="$step"
  ensure_dump_dir
  printf '%s\n' "$program" > "$DUMP_DIR/jq.${step}.jq"
  [[ "$JQ_DEBUG" == "1" ]] && dump_json_pretty_from_file "$in_file" "in.${step}.json"
  jq -c "${jq_args[@]}" "$program" "$in_file" 2> "$DUMP_DIR/jq.${step}.err"
}

run_jq_stdin() {
  local step="$1" program="$2"; shift 2
  local jq_args=("$@")
  LAST_STEP="$step"
  ensure_dump_dir
  printf '%s\n' "$program" > "$DUMP_DIR/jq.${step}.jq"
  local in_file="$DUMP_DIR/in.${step}.raw.json"
  cat > "$in_file"
  [[ "$JQ_DEBUG" == "1" ]] && dump_json_pretty_from_file "$in_file" "in.${step}.json"
  jq -c "${jq_args[@]}" "$program" "$in_file" 2> "$DUMP_DIR/jq.${step}.err"
}

# ---------------------------
# Runtime secret fetch
# ---------------------------
fetch_kc_secret_to_file() {
  local out="$1"
  : "${KCADM_EXEC_MODE:?}"

  case "${KCADM_EXEC_MODE}" in
    kubectl)
      : "${KEYCLOAK_NAMESPACE:?}"
      : "${KEYCLOAK_SECRET_NAME:?}"
      : "${KEYCLOAK_SECRET_KEY:=client-secret}"
      need_cmd kubectl
      kubectl -n "${KEYCLOAK_NAMESPACE}" get secret "${KEYCLOAK_SECRET_NAME}" \
        -o "jsonpath={.data.${KEYCLOAK_SECRET_KEY}}" | base64 -d > "${out}"
      ;;
    docker)
      : "${KEYCLOAK_LOCAL_SECRET_FILE:?KEYCLOAK_LOCAL_SECRET_FILE is required for docker mode}"
      [[ -f "${KEYCLOAK_LOCAL_SECRET_FILE}" ]] || die "local secret file not found: ${KEYCLOAK_LOCAL_SECRET_FILE}"
      cat "${KEYCLOAK_LOCAL_SECRET_FILE}" > "${out}"
      ;;
    *)
      die "Unknown KCADM_EXEC_MODE=${KCADM_EXEC_MODE} (expected docker|kubectl)"
      ;;
  esac

  [[ -s "${out}" ]] || die "Fetched client secret is empty (mode=${KCADM_EXEC_MODE})"
}

SECRET_FILE="$(mktemp -t kc_secret.XXXXXX)"
chmod 600 "${SECRET_FILE}"
fetch_kc_secret_to_file "${SECRET_FILE}"
export KEYCLOAK_CLIENT_SECRET_FILE="${SECRET_FILE}"
trap 'rm -f "$SECRET_FILE" 2>/dev/null || true' EXIT

# ---------------------------
# Validate payload JSON early
# ---------------------------
ensure_dump_dir
dump_file_copy "$TERMS_SYNC_PAYLOAD_FILE" "payload.json.raw"
jq -e . "$TERMS_SYNC_PAYLOAD_FILE" >/dev/null
dump_json_pretty_from_file "$TERMS_SYNC_PAYLOAD_FILE" "payload.json"

# ---------------------------
# PLAN_JSON (desired plan)
# ---------------------------
PLAN_JSON="$(
  run_jq_file "plan_build" '
    def as_array:  if type=="array"  then . else [] end;
    def as_object: if type=="object" then . else {} end;
    def non_empty_obj: (type=="object" and (keys|length)>0);

    . as $p
    | {
        realm_id: $p.realm_id,
        sync_mode: ($p.sync_mode // "replace"),
        allow_delete: ($p.allow_delete // true),
        terms_prefix_root: ($p.terms_prefix_root // "terms"),
        dry_run: ($p.dry_run // false),
        max_retries: ($p.max_retries // 5),
        backoff_ms: ($p.backoff_ms // 400),

        scopes: (
          (
            (($p.client_scopes // []) | as_array)
            + (($p.shared_scopes // []) | as_array)
          )
          | map(. as $s | {
              scope_id:       ($s.scope_id // $s.id // ""),
              scope_name:     ($s.scope_name // ""),
              scope_key:      ($s.scope_key // ""),
              terms_config:     (($s.terms_config // {} | as_object)),
              terms_priority: ($s.terms_priority // "0" | tostring)
            })
          | map(select(.scope_id != ""))
        )
      }
  ' "$TERMS_SYNC_PAYLOAD_FILE"
)"
dump_json_pretty_from_text "plan.json" "$PLAN_JSON"

REALM_ID="$(jq -r '.realm_id' <<<"$PLAN_JSON")"
SYNC_MODE="$(jq -r '.sync_mode' <<<"$PLAN_JSON")"
ALLOW_DELETE="$(jq -r '.allow_delete | if . then "true" else "false" end' <<<"$PLAN_JSON")"
TERMS_PREFIX_ROOT="$(jq -r '.terms_prefix_root' <<<"$PLAN_JSON")"
DRY_RUN="$(jq -r '.dry_run | if . then "true" else "false" end' <<<"$PLAN_JSON")"
MAX_RETRIES="$(jq -r '.max_retries' <<<"$PLAN_JSON")"
BACKOFF_MS="$(jq -r '.backoff_ms' <<<"$PLAN_JSON")"
DESIRED_SCOPE_COUNT="$(jq -r '.scopes|length' <<<"$PLAN_JSON")"

log "Plan: realm=$REALM_ID mode=$SYNC_MODE allow_delete=$ALLOW_DELETE prefix=$TERMS_PREFIX_ROOT dry_run=$DRY_RUN retries=$MAX_RETRIES backoff_ms=$BACKOFF_MS desired_scopes=$DESIRED_SCOPE_COUNT"

kc_login_client_credentials 5 400

fetch_scope_json_to() {
  local scope_id="$1" out="$2"
  kc_exec get "realms/$REALM_ID/client-scopes/$scope_id" >"$out"
}

fetch_all_scopes_json_to() {
  local out="$1"
  kc_exec get "realms/$REALM_ID/client-scopes" >"$out"
}

update_scope_from_file() {
  local scope_id="$1" file="$2"
  [[ -f "$file" ]] || die "update payload file not found (host): $file"
  [[ -s "$file" ]] || die "update payload file is empty (host): $file"

  local err="$DUMP_DIR/kcadm.update.${scope_id}.err"
  : > "$err" || true

  if ! kc_exec update "realms/$REALM_ID/client-scopes/$scope_id" -f - <"$file" >/dev/null 2>"$err"; then
    log "ERROR: update failed scope_id=$scope_id (see $err)"
    sed -n '1,160p' "$err" >&2 || true
    return 1
  fi
}

build_update_representation() {
  local cur_file="$1" desired_terms_config_json="$2" terms_priority="$3" out_file="$4" sid="$5"

  dump_json_pretty_from_file "$cur_file" "cur.${sid}.json"
  dump_json_pretty_from_text "desired.${sid}.json" "$desired_terms_config_json"

  local normalized_terms_config
  normalized_terms_config="$(
    run_jq_stdin "desired_terms_config_normalize.${sid}" '
      def as_object: if type=="object" then . else {} end;
      . as $cfg
      | ($cfg.terms // {} | as_object) as $terms
      | {
          terms: [
            ($terms | keys[] | select(type=="string")) as $k
            | ($terms[$k] // {} | as_object) as $v
            | {
                key: $k,
                title: ($v.title // null),
                required: ($v.required // false),
                version: ($v.version // null),
                url: ($v.url // null)
              }
          ] | sort_by(.key)
        }
    ' <<<"$desired_terms_config_json" | jq -c '.'
  )"

  local program='
    def as_object: if type=="object" then . else {} end;

    . as $cur
    | (.attributes // {} | as_object) as $attrs
    | {
        id: $cur.id,
        name: $cur.name,
        protocol: ($cur.protocol // "openid-connect"),
        attributes:
          (
            $attrs + {
              "terms_config": $terms_config_json_string,
              "terms_priority": ($terms_priority | tostring)
            }
          )
      }
  '

  LAST_STEP="build_update_representation.${sid}"
  ensure_dump_dir
  printf '%s\n' "$program" > "$DUMP_DIR/jq.build_update_representation.${sid}.jq"

  if ! jq -c \
      --arg terms_priority "$terms_priority" \
      --arg terms_config_json_string "$normalized_terms_config" \
      "$program" "$cur_file" \
      >"$out_file" 2>"$DUMP_DIR/jq.build_update_representation.${sid}.err"
  then
    log "ERROR: build_update_representation failed scope_id=$sid (see $DUMP_DIR/jq.build_update_representation.${sid}.err)"
    sed -n '1,160p' "$DUMP_DIR/jq.build_update_representation.${sid}.err" >&2 || true
    return 1
  fi

  dump_json_pretty_from_file "$out_file" "upd.${sid}.json"
}

print_diff_summary() {
  local cur="$1" upd="$2" sid="$3"

  jq -r --arg sid "$sid" '
    (.attributes // {}) as $a
    | input | (.attributes // {}) as $b
    | ($b | keys - ($a | keys)) as $added
    | ($a | keys - ($b | keys)) as $removed
    | ([($b|keys[]) as $k | select(($a[$k] // null) != ($b[$k] // null)) | $k]) as $changed
    | "[DIFF] scope_id=\($sid) summary add=\($added|length) delete=\($removed|length) change=\($changed|length)"
  ' "$cur" "$upd"
}

print_diff_details() {
  local cur="$1" upd="$2" sid="$3" limit="$4"

  jq -r --arg sid "$sid" --argjson limit "$limit" '
    (.attributes // {}) as $a
    | input | (.attributes // {}) as $b
    | (
        [ ($b | keys - ($a | keys))[] | {
            type: "ADD",
            key: .,
            before: null,
            after: $b[.]
          } ]
        +
        [ ($a | keys - ($b | keys))[] | {
            type: "DELETE",
            key: .,
            before: $a[.],
            after: null
          } ]
        +
        [ ($b|keys[]) as $k
          | select(($a[$k] // null) != ($b[$k] // null))
          | select(($a[$k] // "__MISSING__") != "__MISSING__")
          | select(($b[$k] // "__MISSING__") != "__MISSING__")
          | {
              type: "CHANGE",
              key: $k,
              before: $a[$k],
              after: $b[$k]
            }
        ]
      )[:$limit]
    | .[]
    | if .type == "ADD" then
        "[DIFF] scope_id=\($sid) ADD \(.key)=\(.after)"
      elif .type == "DELETE" then
        "[DIFF] scope_id=\($sid) DELETE \(.key) (was=\(.before))"
      else
        "[DIFF] scope_id=\($sid) CHANGE \(.key): \(.before) -> \(.after)"
      end
  ' "$cur" "$upd"
}

verify_scope_terms_policy() {
  local scope_id="$1" expected_terms_config="$2" expected_terms_priority="$3"

  local tmp
  tmp="$(mktemp -t terms_verify.XXXXXX.json)"

  if ! with_retry "$MAX_RETRIES" "$BACKOFF_MS" fetch_scope_json_to "$scope_id" "$tmp"; then
    log "ERROR: verify fetch failed scope_id=$scope_id"
    rm -f "$tmp" || true
    return 1
  fi

  dump_json_pretty_from_file "$tmp" "verify.${scope_id}.json"

  if jq -e     --arg expected_terms_config "$expected_terms_config"     --arg expected_terms_priority "$expected_terms_priority" '
      (.attributes // {}) as $a
      | (($a.terms_config // "") == $expected_terms_config)
      and (($a.terms_priority // "") == $expected_terms_priority)
    ' "$tmp" >/dev/null; then
    rm -f "$tmp" || true
    return 0
  fi

  log "ERROR: verify failed. canonical attributes mismatch. scope_id=$scope_id"
  jq -r --arg expected_terms_config "$expected_terms_config" --arg expected_terms_priority "$expected_terms_priority" '
    (.attributes // {}) as $a
    | "expected terms_config=\($expected_terms_config)",
      "actual   terms_config=\($a.terms_config // "")",
      "expected terms_priority=\($expected_terms_priority)",
      "actual   terms_priority=\($a.terms_priority // "")"
  ' "$tmp" >&2 || true

  rm -f "$tmp" || true
  return 1
}

# ---------------------------
# Discover current managed scopes in Keycloak
# ---------------------------
ALL_SCOPES_FILE="$(mktemp -t terms_all_scopes.XXXXXX.json)"
with_retry "$MAX_RETRIES" "$BACKOFF_MS" fetch_all_scopes_json_to "$ALL_SCOPES_FILE"
dump_json_pretty_from_file "$ALL_SCOPES_FILE" "all_scopes.json"

CURRENT_MANAGED_SCOPES_JSON="$(
  run_jq_file "current_managed_scopes" '
    def as_array:  if type=="array"  then . else [] end;
    def as_object: if type=="object" then . else {} end;

    . | as_array
    | map(
        select(
          (
            (.attributes // {} | as_object | has("terms_config"))
          )
          or
          (
            (.attributes // {} | as_object | has("terms_priority"))
          )
        )
        | {
            scope_id: (.id // ""),
            scope_name: (.name // "")
          }
      )
    | map(select(.scope_id != ""))
  ' "$ALL_SCOPES_FILE"
)"
dump_json_pretty_from_text "current_managed_scopes.json" "$CURRENT_MANAGED_SCOPES_JSON"

CURRENT_MANAGED_SCOPE_COUNT="$(jq -r 'length' <<<"$CURRENT_MANAGED_SCOPES_JSON")"
log "Discovered current managed scopes in Keycloak: $CURRENT_MANAGED_SCOPE_COUNT"

# ---------------------------
# desired ∪ current_managed
# ---------------------------
ALL_SCOPE_IDS_JSON="$(
  jq -cn \
    --argjson desired "$(jq -c '.scopes' <<<"$PLAN_JSON")" \
    --argjson current "$CURRENT_MANAGED_SCOPES_JSON" '
      (
        ($desired | map(.scope_id))
        + ($current | map(.scope_id))
      )
      | unique
  '
)"
dump_json_pretty_from_text "all_scope_ids.json" "$ALL_SCOPE_IDS_JSON"

TOTAL_SCOPE_COUNT="$(jq -r 'length' <<<"$ALL_SCOPE_IDS_JSON")"
log "Reconcile target scopes: total=$TOTAL_SCOPE_COUNT desired=$DESIRED_SCOPE_COUNT current_managed=$CURRENT_MANAGED_SCOPE_COUNT"

rc=0
if [[ "$TOTAL_SCOPE_COUNT" -eq 0 ]]; then
  log "No managed terms scope found in desired/current state. Nothing to do."
  rm -f "$ALL_SCOPES_FILE" || true
  exit 0
fi

mapfile -t SCOPE_IDS < <(jq -r '.[]' <<<"$ALL_SCOPE_IDS_JSON")
for sid in "${SCOPE_IDS[@]}"; do
  [[ -n "$sid" ]] || continue

  cur="$(mktemp -t terms_cur.XXXXXX.json)"
  upd="$(mktemp -t terms_upd.XXXXXX.json)"

  if ! with_retry "$MAX_RETRIES" "$BACKOFF_MS" fetch_scope_json_to "$sid" "$cur"; then
    log "ERROR: fetch failed scope_id=$sid"
    rm -f "$cur" "$upd" 2>/dev/null || true
    rc=1
    continue
  fi

  SCOPE_IN_PLAN="$(
    jq -r --arg sid "$sid" '
      any(.scopes[]?; .scope_id == $sid)
    ' <<<"$PLAN_JSON"
  )"

  desired_terms_config='{}'
  desired_terms_priority='0'
  action='SKIP'

  if [[ "$SCOPE_IN_PLAN" == "true" ]]; then
    desired_terms_config="$(
      run_jq_stdin "desired_terms_config_select.${sid}" '
        def as_array:  if type=="array"  then . else [] end;
        def as_object: if type=="object" then . else {} end;

        (.scopes // [] | as_array)
        | map(select(.scope_id == $sid) | (.terms_config // {} | as_object))
        | .[0] // {}
      ' --arg sid "$sid" <<<"$PLAN_JSON" | jq -c '.'
    )"

    desired_terms_priority="$(
      run_jq_stdin "desired_terms_priority_select.${sid}" '
        def as_array: if type=="array" then . else [] end;

        (.scopes // [] | as_array)
        | map(select(.scope_id == $sid) | (.terms_priority // "0" | tostring))
        | .[0] // "0"
      ' --arg sid "$sid" <<<"$PLAN_JSON" | jq -r '.'
    )"

    terms_count="$(jq -r '((.terms // {}) | if type=="object" then (keys|length) else 0 end)' <<<"$desired_terms_config")"
    action='UPSERT'
    log "[PLAN] scope_id=$sid action=$action desired_terms=$terms_count priority=$desired_terms_priority"
  else
    desired_terms_config='{}'
    desired_terms_priority='0'
    action='UPSERT_EMPTY'
    log "[PLAN] scope_id=$sid action=$action reason=not_in_desired_plan"
  fi

  normalized_terms_config="$(
    run_jq_stdin "verify_terms_config_normalize.${sid}" '
      def as_object: if type=="object" then . else {} end;
      . as $cfg
      | ($cfg.terms // {} | as_object) as $terms
      | {
          terms: [
            ($terms | keys[] | select(type=="string")) as $k
            | ($terms[$k] // {} | as_object) as $v
            | {
                key: $k,
                title: ($v.title // null),
                required: ($v.required // false),
                version: ($v.version // null),
                url: ($v.url // null)
              }
          ] | sort_by(.key)
        }
    ' <<<"$desired_terms_config" | jq -c '.'
  )"

  if ! build_update_representation "$cur" "$desired_terms_config" "$desired_terms_priority" "$upd" "$sid"; then
    rm -f "$cur" "$upd" 2>/dev/null || true
    rc=1
    continue
  fi

  print_diff_summary "$cur" "$upd" "$sid" >&2
  print_diff_details "$cur" "$upd" "$sid" "$DIFF_LOG_LIMIT" >&2

  if cmp -s "$cur" "$upd"; then
    log "[NOOP] scope_id=$sid action=$action no changes detected"
    rm -f "$cur" "$upd" 2>/dev/null || true
    continue
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] scope_id=$sid action=$action update skipped"
    rm -f "$cur" "$upd" 2>/dev/null || true
    continue
  fi

  log "[APPLY] scope_id=$sid action=$action updating"
  if ! with_retry "$MAX_RETRIES" "$BACKOFF_MS" update_scope_from_file "$sid" "$upd"; then
    rm -f "$cur" "$upd" 2>/dev/null || true
    rc=1
    continue
  fi

  log "[APPLY] scope_id=$sid action=$action updated"

  if ! verify_scope_terms_policy "$sid" "$normalized_terms_config" "$desired_terms_priority"; then
    rm -f "$cur" "$upd" 2>/dev/null || true
    rc=1
    continue
  fi

  log "[VERIFY] scope_id=$sid action=$action result=success"

  rm -f "$cur" "$upd" 2>/dev/null || true
done

rm -f "$ALL_SCOPES_FILE" 2>/dev/null || true
exit "$rc"
