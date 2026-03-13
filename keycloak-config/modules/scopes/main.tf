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

  # terms payload
  scope_terms_payloads = {
    for item in flatten([
      for client_key, client in var.clients : [
        for scope_key, scope in client.scopes : {
          key            = "${client_key}.${scope_key}"
          scope_key      = scope_key
          terms_sets     = try(scope.terms_sets, {})
          terms_priority = tostring(try(scope.terms_priority, 100))
        }
      ]
    ]) : item.key => item
    if length(keys(item.terms_sets)) > 0
  }

  shared_scope_terms_payloads = {
    for item in flatten([
      for scope_key, scope in var.shared_scopes : [
        {
          key            = scope_key
          scope_key      = scope_key
          terms_sets     = try(scope.terms_sets, {})
          terms_priority = tostring(try(scope.terms_priority, 10))
        }
      ]
    ]) : item.key => item
    if length(keys(item.terms_sets)) > 0
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

locals {
  terms_sync_client_scopes = [
    for k, v in local.scope_terms_payloads : {
      scope_key       = v.scope_key
      scope_id        = keycloak_openid_client_scope.scopes[k].id
      scope_name      = keycloak_openid_client_scope.scopes[k].name
      terms_sets      = v.terms_sets
      terms_priority  = v.terms_priority
    }
  ]

  terms_sync_shared_scopes = [
    for k, v in local.shared_scope_terms_payloads : {
      scope_key       = v.scope_key
      scope_id        = keycloak_openid_client_scope.shared_scopes[k].id
      scope_name      = keycloak_openid_client_scope.shared_scopes[k].name
      terms_sets      = v.terms_sets
      terms_priority  = v.terms_priority
    }
  ]

  terms_sync_payload = {
    realm_id          = var.realm_id
    sync_mode         = var.terms_sync.mode
    allow_delete      = var.terms_sync.allow_delete
    terms_prefix_root = var.terms_sync.terms_prefix_root
    dry_run           = var.terms_sync.dry_run
    max_retries       = var.terms_sync.max_retries
    backoff_ms        = var.terms_sync.backoff_ms

    client_scopes = local.terms_sync_client_scopes
    shared_scopes = local.terms_sync_shared_scopes
  }

  terms_sync_payload_sha = sha256(jsonencode(local.terms_sync_payload))
}

resource "null_resource" "terms_attributes_sync_all" {
  triggers = {
    payload_sha  = local.terms_sync_payload_sha
    script_rev   = var.terms_sync.script_rev
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
      LOG="$LOG_DIR/terms_sync_all_${var.realm_id}.log"

      PAYLOAD="$(mktemp -t terms_sync_payload.XXXXXX.json)"
      cat > "$PAYLOAD" <<'JSON'
${jsonencode(local.terms_sync_payload)}
JSON

      export TERMS_SYNC_PAYLOAD_FILE="$PAYLOAD"

      /bin/bash "${path.module}/scripts/terms/terms_sync_scopes.sh" >"$LOG" 2>&1 || {
        rc=$?
        echo "[TF] terms sync failed; see log: $LOG" >&2
        exit "$rc"
      }

      echo "[TF] terms sync ok; see log: $LOG" >&2
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

      KEYCLOAK_SECRET_NAME      = "kc-${var.realm_id}-client-credentials"
      KEYCLOAK_SECRET_KEY       = "client-secret"
      KEYCLOAK_LOCAL_SECRET_FILE = "${path.root}/.secrets/kc_${var.realm_id}_client_secret"
    }
  }
}
