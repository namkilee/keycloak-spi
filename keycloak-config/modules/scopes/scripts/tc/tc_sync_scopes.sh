#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=../lib/kc_kcadm.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/kc_kcadm.sh"

need_cmd jq

: "${TC_SYNC_PAYLOAD_FILE:?}"

# ---------------------------
# Debug options
# ---------------------------
JQ_DEBUG="${JQ_DEBUG:-0}"                 # 1이면 jq step마다 입력/프로그램 덤프
DUMP_DIR="${DUMP_DIR:-.tc_sync_debug}"    # 덤프 디렉토리
LAST_STEP="init"

ensure_dump_dir() { mkdir -p "$DUMP_DIR"; }

dump_file_copy() { local src="$1" name="$2"; [[ -f "$src" ]] || return 0; ensure_dump_dir; cp -f "$src" "$DUMP_DIR/$name" 2>/dev/null || true; }
dump_text() { local name="$1" text="$2"; ensure_dump_dir; printf '%s\n' "$text" > "$DUMP_DIR/$name" 2>/dev/null || true; }

dump_json_pretty_from_file() {
  local src="$1" name="$2"
  [[ -f "$src" ]] || return 0
  ensure_dump_dir
  if jq '.' "$src" > "$DUMP_DIR/$name" 2>/dev/null; then :; else cp -f "$src" "$DUMP_DIR/$name.raw" 2>/dev/null || true; fi
}

dump_json_pretty_from_text() {
  local name="$1" json="$2"
  ensure_dump_dir
  if printf '%s\n' "$json" | jq '.' > "$DUMP_DIR/$name" 2>/dev/null; then :; else printf '%s\n' "$json" > "$DUMP_DIR/$name.raw" 2>/dev/null || true; fi
}

on_err() {
  local exit_code=$?
  echo "[FATAL] failed (exit=$exit_code) step=$LAST_STEP at line=${BASH_LINENO[0]} cmd=${BASH_COMMAND}" >&2
  echo "[FATAL] debug dump dir: $DUMP_DIR" >&2
  dump_file_copy "$TC_SYNC_PAYLOAD_FILE" "payload.json.raw"
  dump_json_pretty_from_file "$TC_SYNC_PAYLOAD_FILE" "payload.json"
  exit "$exit_code"
}
trap on_err ERR

# ---------------------------
# jq runner (supports jq args like --arg/--argjson)
# ---------------------------
run_jq_file() {
  # run_jq_file <step_name> <jq_program> <input_file> [jq_args...]
  local step="$1" program="$2" in_file="$3"
  shift 3
  local jq_args=("$@")

  LAST_STEP="$step"
  ensure_dump_dir
  printf '%s\n' "$program" > "$DUMP_DIR/jq.${step}.jq"

  if [[ "$JQ_DEBUG" == "1" ]]; then
    dump_json_pretty_from_file "$in_file" "in.${step}.json"
  fi

  local out
  if ! out="$(jq -c "${jq_args[@]}" "$program" "$in_file" 2> "$DUMP_DIR/jq.${step}.err")"; then
    echo "[FATAL] jq failed step=$step" >&2
    echo "[FATAL] jq stderr:" >&2
    sed -n '1,160p' "$DUMP_DIR/jq.${step}.err" >&2 || true
    echo "[FATAL] input(head):" >&2
    head -c 2000 "$in_file" >&2 || true; echo >&2
    echo "[FATAL] input(tail):" >&2
    tail -c 2000 "$in_file" >&2 || true; echo >&2
    return 1
  fi
  printf '%s\n' "$out"
}

run_jq_stdin() {
  # run_jq_stdin <step_name> <jq_program> [jq_args...]
  local step="$1" program="$2"
  shift 2
  local jq_args=("$@")

  LAST_STEP="$step"
  ensure_dump_dir
  printf '%s\n' "$program" > "$DUMP_DIR/jq.${step}.jq"

  local in_file="$DUMP_DIR/in.${step}.raw.json"
  cat > "$in_file"

  if [[ "$JQ_DEBUG" == "1" ]]; then
    dump_json_pretty_from_file "$in_file" "in.${step}.json"
  fi

  local out
  if ! out="$(jq -c "${jq_args[@]}" "$program" "$in_file" 2> "$DUMP_DIR/jq.${step}.err")"; then
    echo "[FATAL] jq failed step=$step" >&2
    echo "[FATAL] jq stderr:" >&2
    sed -n '1,160p' "$DUMP_DIR/jq.${step}.err" >&2 || true
    return 1
  fi
  printf '%s\n' "$out"
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
dump_file_copy "$TC_SYNC_PAYLOAD_FILE" "payload.json.raw"
jq -e . "$TC_SYNC_PAYLOAD_FILE" >/dev/null
dump_json_pretty_from_file "$TC_SYNC_PAYLOAD_FILE" "payload.json"

# ---------------------------
# Build PLAN_JSON (NULL SAFE)
# ---------------------------
PLAN_JSON="$(
  run_jq_file "plan_build" '
    def as_array:  if type=="array"  then . else [] end;
    def as_object: if type=="object" then . else {} end;

    . as $p
    | {
        realm_id: $p.realm_id,
        sync_mode: ($p.sync_mode // "replace"),
        allow_delete: ($p.allow_delete // true),
        tc_prefix_root: ($p.tc_prefix_root // "tc"),
        dry_run: ($p.dry_run // false),
        max_retries: ($p.max_retries // 5),
        backoff_ms: ($p.backoff_ms // 400),
        scopes: (
          (
            (($p.client_scopes // []) | as_array)
            + (($p.shared_scopes // []) | as_array)
          )
          | map(
              . as $s
              | {
                  scope_id:   ($s.scope_id // $s.id // ""),
                  scope_name: ($s.scope_name // ""),
                  scope_key:  ($s.scope_key // ""),
                  tc_sets:    (($s.tc_sets // {}) | as_object)
                }
            )
          | map(select(.scope_id != ""))
        )
      }
  ' "$TC_SYNC_PAYLOAD_FILE"
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

log "Plan: realm=$REALM_ID mode=$SYNC_MODE allow_delete=$ALLOW_DELETE prefix=$TC_PREFIX_ROOT dry_run=$DRY_RUN retries=$MAX_RETRIES backoff_ms=$BACKOFF_MS scopes=$SCOPE_COUNT"

kc_login_client_credentials 5 400

fetch_scope_json_to() {
  local scope_id="$1" out="$2"
  kc_exec get "realms/$REALM_ID/client-scopes/$scope_id" >"$out"
}

# ---------------------------
# UPDATE via stdin (container-safe)
# ---------------------------
update_scope_from_file() {
  local scope_id="$1" file="$2"
  [[ -f "$file" ]] || die "update payload file not found (host): $file"
  [[ -s "$file" ]] || die "update payload file is empty (host): $file"

  # stderr 캡처해서 원인 파악 쉽게
  local err="$DUMP_DIR/kcadm.update.${scope_id}.err"
  : > "$err" || true

  if ! kc_exec update "realms/$REALM_ID/client-scopes/$scope_id" -f - <"$file" >/dev/null 2>"$err"; then
    log "ERROR: update failed scope_id=$scope_id (see $err)"
    # 에러가 길면 앞부분만 콘솔에도 보여주기
    sed -n '1,120p' "$err" >&2 || true
    return 1
  fi
}

# ---------------------------
# build_update_representation (NULL SAFE)
# ---------------------------
build_update_representation() {
  local cur_file="$1" desired_tc_sets_json="$2" out_file="$3" sid="$4"

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
    | (
        if $mode == "replace" then
          (if $allow_delete == "true"
            then ($a | with_entries(select(.key | startswith($prefix + ".") | not)))
            else $a
          end)
          + $want
        else
          $a + $want
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

verify_scope_has_prefix_keys() {
  local scope_id="$1"
  local tmp
  tmp="$(mktemp -t tc_verify.XXXXXX.json)"

  if ! with_retry "$MAX_RETRIES" "$BACKOFF_MS" fetch_scope_json_to "$scope_id" "$tmp"; then
    log "ERROR: verify fetch failed scope_id=$scope_id"
    rm -f "$tmp" || true
    return 1
  fi

  if jq -e --arg p "$TC_PREFIX_ROOT" '
      (.attributes // {}) | keys | map(startswith($p + ".")) | any
    ' "$tmp" >/dev/null; then
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
  log "No scopes in payload. Nothing to do."
  exit 0
fi

# subshell rc bug 방지: mapfile로 받기
mapfile -t SCOPE_IDS < <(jq -r '.scopes[].scope_id' <<<"$PLAN_JSON" 2>/dev/null || true)
if [[ "${#SCOPE_IDS[@]}" -eq 0 ]]; then
  log "No valid scope_id found in PLAN_JSON. Nothing to do."
  exit 0
fi

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

  build_update_representation "$cur" "$desired_tc_sets" "$upd" "$sid"
  print_diff "$cur" "$upd" "$sid" >&2

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] skip update scope_id=$sid"
    continue
  fi

  log "UPDATING scope_id=$sid"
  # 업데이트는 stdin 방식: 컨테이너 파일 불필요
  if ! with_retry "$MAX_RETRIES" "$BACKOFF_MS" update_scope_from_file "$sid" "$upd"; then
    rc=1
    continue
  fi
  log "UPDATED scope_id=$sid"

  if ! verify_scope_has_prefix_keys "$sid"; then
    rc=1
    continue
  fi
done

exit "$rc"
