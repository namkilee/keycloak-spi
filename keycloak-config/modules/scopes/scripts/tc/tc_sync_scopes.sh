#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/kc_kcadm.sh"

need_cmd jq
: "${TC_SYNC_PAYLOAD_FILE:?}"

# ---------------------------
# Debug options
# ---------------------------
JQ_DEBUG="${JQ_DEBUG:-0}"
DUMP_DIR="${DUMP_DIR:-.tc_sync_debug}"
LAST_STEP="init"

# 정책 옵션: tc_sets가 비어있는 scope를 어떻게 처리할지
TC_EMPTY_MEANS_DELETE="${TC_EMPTY_MEANS_DELETE:-false}"  # true|false

ensure_dump_dir() { mkdir -p "$DUMP_DIR"; }

dump_file_copy() { local src="$1" name="$2"; [[ -f "$src" ]] || return 0; ensure_dump_dir; cp -f "$src" "$DUMP_DIR/$name" 2>/dev/null || true; }
dump_json_pretty_from_file() { local src="$1" name="$2"; [[ -f "$src" ]] || return 0; ensure_dump_dir; jq '.' "$src" > "$DUMP_DIR/$name" 2>/dev/null || cp -f "$src" "$DUMP_DIR/$name.raw" 2>/dev/null || true; }
dump_json_pretty_from_text() { local name="$1" json="$2"; ensure_dump_dir; printf '%s\n' "$json" | jq '.' > "$DUMP_DIR/$name" 2>/dev/null || printf '%s\n' "$json" > "$DUMP_DIR/$name.raw" 2>/dev/null || true; }

on_err() {
  local exit_code=$?
  echo "[FATAL] failed (exit=$exit_code) step=$LAST_STEP at line=${BASH_LINENO[0]} cmd=${BASH_COMMAND}" >&2
  echo "[FATAL] dump dir: $DUMP_DIR" >&2
  dump_file_copy "$TC_SYNC_PAYLOAD_FILE" "payload.json.raw"
  dump_json_pretty_from_file "$TC_SYNC_PAYLOAD_FILE" "payload.json"
  exit "$exit_code"
}
trap on_err ERR

# jq runner (supports jq args)
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
# Runtime secret fetch (NO terraform sensitive)
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
    *) die "Unknown KCADM_EXEC_MODE=${KCADM_EXEC_MODE} (expected docker|kubectl)";;
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
dump_file_copy "$TC_SYNC_PAYLOAD_FILE" "payload.json.raw"
jq -e . "$TC_SYNC_PAYLOAD_FILE" >/dev/null
dump_json_pretty_from_file "$TC_SYNC_PAYLOAD_FILE" "payload.json"

# ---------------------------
# PLAN_JSON (TC 대상만 scopes에 남기기)
# - tc_sets 비어있으면 제외 (기본)
# - 단, TC_EMPTY_MEANS_DELETE=true면 비어있는 tc_sets도 포함
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
        tc_prefix_root: ($p.tc_prefix_root // "tc"),
        dry_run: ($p.dry_run // false),
        max_retries: ($p.max_retries // 5),
        backoff_ms: ($p.backoff_ms // 400),
        tc_empty_means_delete: ($tc_empty_means_delete == "true"),

        scopes: (
          (
            (($p.client_scopes // []) | as_array)
            + (($p.shared_scopes // []) | as_array)
          )
          | map(. as $s | {
            scope_id:    ($s.scope_id // $s.id // ""),
            scope_name:  ($s.scope_name // ""),
            scope_key:   ($s.scope_key // ""),
            tc_sets:     (($s.tc_sets // {}) | as_object),
            tc_priority: ($s.tc_priority // "0" | tostring)
          })
          | map(select(.scope_id != ""))
          | map(
              if ($tc_empty_means_delete == "true") then
                .                         # empty tc_sets도 포함(삭제 시나리오)
              else
                select(.tc_sets | non_empty_obj)   # tc_sets 비어있으면 제외
              end
            )
        )
      }
  ' "$TC_SYNC_PAYLOAD_FILE" --arg tc_empty_means_delete "$TC_EMPTY_MEANS_DELETE"
)"
dump_json_pretty_from_text "plan.json" "$PLAN_JSON"

REALM_ID="$(jq -r '.realm_id' <<<"$PLAN_JSON")"
SYNC_MODE="$(jq -r '.sync_mode' <<<"$PLAN_JSON")"
ALLOW_DELETE="$(jq -r '.allow_delete | if . then "true" else "false" end' <<<"$PLAN_JSON")"
TC_PREFIX_ROOT="$(jq -r '.tc_prefix_root' <<<"$PLAN_JSON")"
DRY_RUN="$(jq -r '.dry_run | if . then "true" else "false" end' <<<"$PLAN_JSON")"
MAX_RETRIES="$(jq -r '.max_retries' <<<"$PLAN_JSON")"
BACKOFF_MS="$(jq -r '.backoff_ms' <<<"$PLAN_JSON")"
SCOPE_COUNT="$(jq -r '.scopes|length' <<<"$PLAN_JSON")"
PLAN_EMPTY_DELETE="$(jq -r '.tc_empty_means_delete | if . then "true" else "false" end' <<<"$PLAN_JSON")"

log "Plan: realm=$REALM_ID mode=$SYNC_MODE allow_delete=$ALLOW_DELETE prefix=$TC_PREFIX_ROOT dry_run=$DRY_RUN retries=$MAX_RETRIES backoff_ms=$BACKOFF_MS scopes=$SCOPE_COUNT tc_empty_means_delete=$PLAN_EMPTY_DELETE"

kc_login_client_credentials 5 400

fetch_scope_json_to() {
  local scope_id="$1" out="$2"
  kc_exec get "realms/$REALM_ID/client-scopes/$scope_id" >"$out"
}

# stdin update
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
  local cur_file="$1" desired_tc_sets_json="$2" tc_priority="$3" out_file="$4" sid="$5"

  dump_json_pretty_from_file "$cur_file" "cur.${sid}.json"
  dump_json_pretty_from_text "desired.${sid}.json" "$desired_tc_sets_json"

  local safe_tc_sets
  safe_tc_sets="$(
    run_jq_stdin "desired_tc_sets_normalize.${sid}" '
      def as_object: if type=="object" then . else {} end;
      . | as_object
    ' <<<"$desired_tc_sets_json" | jq -c '.'
  )"

  local program='
    def as_object: if type=="object" then . else {} end;
    def k($tc_key; $field): "\($prefix).\($tc_key).\($field)";

    def desired_tc_map($tc_sets):
      ($tc_sets | as_object | to_entries)
      | map(.key as $tc_key | (.value | as_object) as $tc |
          [
            {key: k($tc_key;"required"), value: (if ($tc.required // false) then "true" else "false" end)},
            {key: k($tc_key;"version"),  value: (($tc.version // "")|tostring)},
            (if ($tc.title? and ($tc.title|tostring|length)>0) then {key:k($tc_key;"title"), value:($tc.title|tostring)} else empty end),
            (if ($tc.url? and ($tc.url|tostring|length)>0) then {key:k($tc_key;"url"), value:($tc.url|tostring)} else empty end),
            (if ($tc.template? and ($tc.template|tostring|length)>0) then {key:k($tc_key;"template"), value:($tc.template|tostring)} else empty end)
          ]
      )
      | add
      | (if . == null then {} else from_entries end);

    . as $cur
    | (.attributes // {} | as_object) as $a
    | desired_tc_map($tc_sets) as $want
    | ($want + { "tc_priority": ($tc_priority|tostring) }) as $want2
    | (
        if $mode == "replace" then
          (if $allow_delete == "true"
            then ($a | with_entries(select(.key | startswith($prefix + ".") | not)))
            else $a
          end)
          + $want2
        else
          $a + $want2
        end
      ) as $new_attrs
    | ($cur | .attributes = $new_attrs)
  '

  LAST_STEP="build_update_representation.${sid}"
  ensure_dump_dir
  printf '%s\n' "$program" > "$DUMP_DIR/jq.build_update_representation.${sid}.jq"

  if ! jq -c \
      --arg mode "$SYNC_MODE" \
      --arg prefix "$TC_PREFIX_ROOT" \
      --arg allow_delete "$ALLOW_DELETE" \
      --arg tc_priority "$tc_priority" \
      --argjson tc_sets "$safe_tc_sets" \
      "$program" "$cur_file" \
      >"$out_file" 2>"$DUMP_DIR/jq.build_update_representation.${sid}.err"
  then
    log "ERROR: build_update_representation failed scope_id=$sid (see $DUMP_DIR/jq.build_update_representation.${sid}.err)"
    sed -n '1,160p' "$DUMP_DIR/jq.build_update_representation.${sid}.err" >&2 || true
    return 1
  fi

  dump_json_pretty_from_file "$out_file" "upd.${sid}.json"
}

print_diff() {
  local cur="$1" upd="$2" sid="$3"
  jq -r --arg sid "$sid" '
    (.attributes // {}) as $a
    | input | (.attributes // {}) as $b
    | ($b | keys - ($a | keys)) as $added
    | ($a | keys - ($b | keys)) as $removed
    | ([($b|keys[]) as $k | select(($a[$k] // null) != ($b[$k] // null)) | $k]) as $changed
    | "[SCOPE \($sid)] +\($added|length) -\($removed|length) ~\($changed|length)"
  ' "$cur" "$upd"
}

# verify 정책:
# - tc_sets가 비어있지 않은 scope는 prefix 키가 있어야 한다(기본)
# - TC_EMPTY_MEANS_DELETE=true & tc_sets empty면: "prefix 키가 없어도 OK" (삭제 시나리오)
verify_scope_tc_policy() {
  local scope_id="$1" desired_tc_sets_json="$2"

  # tc_sets 비었는지
  local tc_count
  tc_count="$(jq -r 'if type=="object" then (keys|length) else 0 end' <<<"$desired_tc_sets_json")"

  # empty=delete 모드 + empty tc_sets => prefix 키가 "없어도" 정상
  if [[ "$PLAN_EMPTY_DELETE" == "true" && "$tc_count" -eq 0 ]]; then
    log "VERIFY SKIP(scope_id=$scope_id): tc_sets empty and tc_empty_means_delete=true (prefix keys may be absent)"
    return 0
  fi

  # 기본: prefix 키가 반드시 있어야 함
  local tmp
  tmp="$(mktemp -t tc_verify.XXXXXX.json)"
  if ! with_retry "$MAX_RETRIES" "$BACKOFF_MS" fetch_scope_json_to "$scope_id" "$tmp"; then
    log "ERROR: verify fetch failed scope_id=$scope_id"
    rm -f "$tmp" || true
    return 1
  fi

  if jq -e --arg p "$TC_PREFIX_ROOT" '(.attributes // {}) | keys | map(startswith($p + ".")) | any' "$tmp" >/dev/null; then
    rm -f "$tmp" || true
    return 0
  fi

  log "ERROR: verify failed. No keys with prefix=${TC_PREFIX_ROOT}. scope_id=$scope_id"
  jq -r --arg p "$TC_PREFIX_ROOT" '
    (.attributes // {}) | to_entries
    | map(select(.key | startswith($p + ".")))
    | .[:50]
    | if length == 0 then "(no matching attributes)" else (map("\(.key)=\(.value)") | join("\n")) end
  ' "$tmp" >&2 || true

  rm -f "$tmp" || true
  return 1
}

rc=0
if [[ "$SCOPE_COUNT" -eq 0 ]]; then
  log "No TC target scopes in plan. Nothing to do."
  exit 0
fi

mapfile -t SCOPE_IDS < <(jq -r '.scopes[].scope_id' <<<"$PLAN_JSON")
for sid in "${SCOPE_IDS[@]}"; do
  [[ -n "$sid" ]] || continue

  cur="$(mktemp -t tc_cur.XXXXXX.json)"
  upd="$(mktemp -t tc_upd.XXXXXX.json)"
  cleanup_files() { rm -f "$cur" "$upd" 2>/dev/null || true; }
  trap cleanup_files RETURN

  if ! with_retry "$MAX_RETRIES" "$BACKOFF_MS" fetch_scope_json_to "$sid" "$cur"; then
    log "ERROR: fetch failed scope_id=$sid"
    rc=1
    continue
  fi

  desired_tc_sets="$(
    run_jq_stdin "desired_tc_sets_select.${sid}" '
      def as_array:  if type=="array"  then . else [] end;
      def as_object: if type=="object" then . else {} end;

      (.scopes // [] | as_array)
      | map(select(.scope_id == $sid) | (.tc_sets // {} | as_object))
      | .[0] // {}
    ' --arg sid "$sid" <<<"$PLAN_JSON" | jq -c '.'
  )"

  desired_tc_priority="$(
  run_jq_stdin "desired_tc_priority_select.${sid}" '
    def as_array: if type=="array" then . else [] end;

    (.scopes // [] | as_array)
    | map(select(.scope_id == $sid) | (.tc_priority // "0" | tostring))
    | .[0] // "0"
  ' --arg sid "$sid" <<<"$PLAN_JSON" | jq -r '.'
)"


  build_update_representation "$cur" "$desired_tc_sets" "$desired_tc_priority" "$upd" "$sid"
  print_diff "$cur" "$upd" "$sid" >&2

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] skip update scope_id=$sid"
    continue
  fi

  log "UPDATING scope_id=$sid (stdin)"
  if ! with_retry "$MAX_RETRIES" "$BACKOFF_MS" update_scope_from_file "$sid" "$upd"; then
    rc=1
    continue
  fi
  log "UPDATED scope_id=$sid"

  if ! verify_scope_tc_policy "$sid" "$desired_tc_sets"; then
    rc=1
    continue
  fi
done

exit "$rc"
