locals {
  client_scopes = {
    for item in flatten([
      for client_key, client in var.clients : [
        for scope_key, scope in client.scopes : {
          key         = "${client_key}.${scope_key}"
          client_key  = client_key
          client_id   = client.client_id
          scope_key   = scope_key
          description = scope.description
        }
      ]
    ]) : item.key => item
  }

  shared_scopes = {
    for scope_key, scope in var.shared_scopes : scope_key => {
      scope_key   = scope_key
      description = scope.description
    }
  }

  client_mappers = {
    for item in flatten([
      for client_key, client in var.clients : [
        for mapper in client.mappers : {
          key                = "${client_key}.${mapper.name}"
          client_key         = client_key
          scope_resource_key = "${client_key}.${mapper.scope}"
          name               = mapper.name
          protocol_mapper    = mapper.protocol_mapper
          config             = mapper.config
        }
      ]
    ]) : item.key => item
  }

  shared_mappers = {
    for item in flatten([
      for scope_key, scope in var.shared_scopes : [
        for mapper in try(scope.mappers, []) : {
          key             = "${scope_key}.${mapper.name}"
          scope_key       = scope_key
          name            = mapper.name
          protocol_mapper = mapper.protocol_mapper
          config          = mapper.config
        }
      ]
    ]) : item.key => item
  }

  # tc payload
  scope_tc_payloads = {
    for item in flatten([
      for client_key, client in var.clients : [
        for scope_key, scope in client.scopes : {
          key         = "${client_key}.${scope_key}"
          scope_key   = scope_key
          tc_sets     = try(scope.tc_sets, null)
          tc_priority = tostring(try(scope.tc_priority, 100))
        }
      ]
    ]) : item.key => item
    if item.tc_sets != null
  }


  shared_scope_tc_payloads = {
    for item in flatten([
      for scope_key, scope in var.shared_scopes : [
        {
          key         = scope_key
          scope_key   = scope_key
          tc_sets     = try(scope.tc_sets, null)
          tc_priority = tostring(try(scope.tc_priority, 10))
        }
      ]
    ]) : item.key => item
    if item.tc_sets != null
  }
}

resource "keycloak_openid_client_scope" "scopes" {
  for_each = local.client_scopes

  realm_id               = var.realm_id
  name                   = "${each.value.scope_key}-${each.value.client_id}"
  description            = each.value.description != "" ? each.value.description : "Client scope for ${each.value.scope_key}"
  consent_screen_text    = each.value.scope_key
  include_in_token_scope = true
}

resource "keycloak_openid_client_scope" "shared_scopes" {
  for_each = local.shared_scopes

  realm_id               = var.realm_id
  name                   = each.value.scope_key
  description            = each.value.description != "" ? each.value.description : "Shared client scope for ${each.value.scope_key}"
  consent_screen_text    = each.value.scope_key
  include_in_token_scope = true
}

resource "keycloak_generic_protocol_mapper" "value_transform" {
  for_each = local.client_mappers

  realm_id        = var.realm_id
  client_scope_id = keycloak_openid_client_scope.scopes[each.value.scope_resource_key].id
  name            = each.value.name
  protocol        = "openid-connect"
  protocol_mapper = each.value.protocol_mapper
  config          = each.value.config
}

resource "keycloak_generic_protocol_mapper" "shared" {
  for_each = local.shared_mappers

  realm_id        = var.realm_id
  client_scope_id = keycloak_openid_client_scope.shared_scopes[each.value.scope_key].id
  name            = each.value.name
  protocol        = "openid-connect"
  protocol_mapper = each.value.protocol_mapper
  config          = each.value.config
}

# =========================
# TC sync payload (realm 단일)
# =========================
locals {
  tc_sync_client_scopes = [
    for k, v in local.scope_tc_payloads : {
      scope_key    = v.scope_key
      scope_id     = keycloak_openid_client_scope.scopes[k].id
      scope_name   = keycloak_openid_client_scope.scopes[k].name
      tc_sets      = v.tc_sets
      tc_priority  = v.tc_priority
    }
  ]

  tc_sync_shared_scopes = [
    for k, v in local.shared_scope_tc_payloads : {
      scope_key    = v.scope_key
      scope_id     = keycloak_openid_client_scope.shared_scopes[k].id
      scope_name   = keycloak_openid_client_scope.shared_scopes[k].name
      tc_sets      = v.tc_sets
      tc_priority  = v.tc_priority
    }
  ]

  tc_sync_payload = {
    realm_id       = var.realm_id
    sync_mode      = var.tc_sync.mode
    allow_delete   = var.tc_sync.allow_delete
    tc_prefix_root = var.tc_sync.tc_prefix_root
    dry_run        = var.tc_sync.dry_run
    max_retries    = var.tc_sync.max_retries
    backoff_ms     = var.tc_sync.backoff_ms

    client_scopes = local.tc_sync_client_scopes
    shared_scopes = local.tc_sync_shared_scopes
  }

  tc_sync_payload_sha = sha256(jsonencode(local.tc_sync_payload))
}

resource "null_resource" "tc_attributes_sync_all" {
  triggers = {
    payload_sha  = local.tc_sync_payload_sha
    script_rev   = var.tc_sync.script_rev
    realm_id     = var.realm_id
    keycloak_url = var.keycloak_url
    exec_mode    = var.kcadm_exec_mode
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command = <<-EOT
      set -Eeuo pipefail

      LOG_DIR="${path.root}/.tf-logs"
      mkdir -p "$LOG_DIR"
      chmod 700 "$LOG_DIR"
      LOG="$LOG_DIR/tc_sync_all_${var.realm_id}.log"

      PAYLOAD="$(mktemp -t tc_sync_payload.XXXXXX.json)"
      cat > "$PAYLOAD" <<'JSON'
${jsonencode(local.tc_sync_payload)}
JSON

      export TC_SYNC_PAYLOAD_FILE="$PAYLOAD"

      /bin/bash "${path.module}/scripts/tc/tc_sync_scopes.sh" >"$LOG" 2>&1 || {
        rc=$?
        echo "[TF] tc sync failed; see log: $LOG" >&2
        exit "$rc"
      }

      echo "[TF] tc sync ok; see log: $LOG" >&2
    EOT

    environment = {
      KCADM_EXEC_MODE         = var.kcadm_exec_mode
      KCADM_PATH              = var.keycloak_kcadm_path
      KEYCLOAK_CONTAINER_NAME = var.keycloak_container_name
      KEYCLOAK_NAMESPACE      = var.keycloak_namespace
      KEYCLOAK_POD_SELECTOR   = var.keycloak_pod_selector

      KEYCLOAK_URL        = var.keycloak_url
      KEYCLOAK_AUTH_REALM = var.keycloak_auth_realm
      KEYCLOAK_CLIENT_ID  = var.keycloak_client_id

      # k8s에서 읽을 secret (bootstrap이 이 이름으로 생성해둠)
      KEYCLOAK_SECRET_NAME = "kc-${var.realm_id}-client-credentials"
      KEYCLOAK_SECRET_KEY  = "client-secret"

      # docker(dev)에서 읽을 로컬 파일 (bootstrap이 이 파일을 생성해둠)
      KEYCLOAK_LOCAL_SECRET_FILE = "${path.root}/.secrets/kc_${var.realm_id}_client_secret"
    }
  }
}
