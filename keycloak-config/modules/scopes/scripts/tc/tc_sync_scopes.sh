#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=../lib/kc_kcadm.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/kc_kcadm.sh"

need_cmd jq

: "${TC_SYNC_PAYLOAD_FILE:?}"

PLAN_JSON="$(jq -c '
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
        (($p.client_scopes // []) + ($p.shared_scopes // []))
        | map({
            scope_id: .scope_id,
            scope_name: (.scope_name // ""),
            scope_key: (.scope_key // ""),
            tc_sets: (.tc_sets // {})
          })
      )
    }
' "$TC_SYNC_PAYLOAD_FILE")"

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

update_scope_from_file() {
  local scope_id="$1" file="$2"
  kc_exec update "realms/$REALM_ID/client-scopes/$scope_id" -f "$file" >/dev/null
}

# 핵심: "부분 JSON({attributes:{...}})"이 아니라
#          "현재 representation 전체"에서 attributes만 교체한 JSON을 만들어 PUT 한다.
build_update_representation() {
  local cur="$1" desired_tc_sets="$2" out="$3"

  jq -c \
    --arg mode "$SYNC_MODE" \
    --arg prefix "$TC_PREFIX_ROOT" \
    --arg allow_delete "$ALLOW_DELETE" \
    --argjson tc_sets "$desired_tc_sets" '
    def k($tc_key; $field): "\($prefix).\($tc_key).\($field)";

    def desired_tc_map:
      ($tc_sets | to_entries)
      | map(.key as $tc_key | .value as $tc |
          [
            {key: k($tc_key;"required"), value: (if ($tc.required // false) then "true" else "false" end)},
            {key: k($tc_key;"version"),  value: (($tc.version // "")|tostring)},
            (if ($tc.title? and ($tc.title|tostring|length)>0) then {key:k($tc_key;"title"), value:($tc.title|tostring)} else empty end),
            (if ($tc.url? and ($tc.url|tostring|length)>0) then {key:k($tc_key;"url"), value:($tc.url|tostring)} else empty end),
            (if ($tc.template? and ($tc.template|tostring|length)>0) then {key:k($tc_key;"template"), value:($tc.template|tostring)} else empty end)
          ]
      )
      | add
      | from_entries;

    . as $cur
    | (.attributes // {}) as $a
    | (desired_tc_map) as $want
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
  ' "$cur" >"$out"
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

  # 디버그: attributes 일부 출력(너무 길면 불편하니 prefix 근처만)
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

jq -r '.scopes[].scope_id' <<<"$PLAN_JSON" | while read -r sid; do
  [[ -n "$sid" ]] || continue

  cur="$(mktemp -t tc_cur.XXXXXX.json)"
  upd="$(mktemp -t tc_upd.XXXXXX.json)"
  cleanup() { rm -f "$cur" "$upd" 2>/dev/null || true; }
  trap cleanup RETURN

  if ! with_retry "$MAX_RETRIES" "$BACKOFF_MS" fetch_scope_json_to "$sid" "$cur"; then
    log "ERROR: fetch failed scope_id=$sid"
    rc=1
    continue
  fi

  desired_tc_sets="$(jq -c --arg sid "$sid" '
    .scopes[] | select(.scope_id == $sid) | (.tc_sets // {})
  ' <<<"$PLAN_JSON")"

  # representation 전체를 만들어 update
  build_update_representation "$cur" "$desired_tc_sets" "$upd"
  print_diff "$cur" "$upd" "$sid" >&2

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] skip update scope_id=$sid"
    continue
  fi

  log "UPDATING scope_id=$sid"
  if ! with_retry "$MAX_RETRIES" "$BACKOFF_MS" update_scope_from_file "$sid" "$upd"; then
    log "ERROR: update failed scope_id=$sid"
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
