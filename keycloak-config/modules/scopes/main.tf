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

  # scope 별 tc_sets payload (ex: terms, marketing ...)
  # key: "<client_key>.<scope_key>"
  scope_tc_payloads = {
    for item in flatten([
      for client_key, client in var.clients : [
        for scope_key, scope in client.scopes : {
          key       = "${client_key}.${scope_key}"
          scope_key = scope_key
          tc_sets   = try(scope.tc_sets, null)
        }
      ]
    ]) : item.key => item
    if item.tc_sets != null
  }

  shared_scope_tc_payloads = {
    for item in flatten([
      for scope_key, scope in var.shared_scopes : [
        {
          key       = scope_key
          scope_key = scope_key
          tc_sets   = try(scope.tc_sets, null)
        }
      ]
    ]) : item.key => item
    if item.tc_sets != null
  }

  scope_tc_script_rev = "rev-0.1"
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
# scope 별 tc attributes 완전 동기화(삭제 포함)
# =========================
resource "null_resource" "scope_tc_attributes" {
  for_each = local.scope_tc_payloads

  triggers = {
    scope_id       = keycloak_openid_client_scope.scopes[each.key].id
    scope_key      = each.value.scope_key
    scope_name     = keycloak_openid_client_scope.scopes[each.key].name

    tc_sets_json   = jsonencode(each.value.tc_sets)
    tc_sets_sha256 = sha256(jsonencode(each.value.tc_sets))
    script_rev     = local.scope_tc_script_rev
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]

    command = <<-EOT
      set -euxo pipefail
      ${path.module}/scripts/scope_tc_attributes_sync.sh
    EOT

    environment = {
      KCADM_EXEC_MODE        = var.kcadm_exec_mode
      KCADM_PATH             = var.keycloak_kcadm_path
      KEYCLOAK_CONTAINER_NAME= var.keycloak_container_name
      KEYCLOAK_NAMESPACE     = var.keycloak_namespace
      KEYCLOAK_POD_SELECTOR  = var.keycloak_pod_selector
      KEYCLOAK_URL           = var.keycloak_url
      KEYCLOAK_AUTH_REALM    = var.keycloak_auth_realm
      KEYCLOAK_CLIENT_ID     = var.keycloak_client_id
      KEYCLOAK_CLIENT_SECRET = var.keycloak_client_secret
      REALM_ID               = var.realm_id
      SCOPE_ID               = self.triggers.scope_id
      SCOPE_KEY              = self.triggers.scope_key
      SCOPE_NAME             = self.triggers.scope_name
      TC_SETS_JSON           = self.triggers.tc_sets_json
      TC_PREFIX_ROOT         = "tc"
      SYNC_MODE              = "replace"
    }
  }


  depends_on = [
    keycloak_openid_client_scope.scopes,
    keycloak_generic_protocol_mapper.value_transform,
  ]
}

# =========================
# shared scope tc attributes 완전 동기화(삭제 포함)
# =========================
resource "null_resource" "shared_scope_tc_attributes" {
  for_each = local.shared_scope_tc_payloads

  triggers = {
    scope_id       = keycloak_openid_client_scope.shared_scopes[each.key].id
    scope_key      = each.value.scope_key
    scope_name     = keycloak_openid_client_scope.shared_scopes[each.key].name

    tc_sets_json   = jsonencode(each.value.tc_sets)
    tc_sets_sha256 = sha256(jsonencode(each.value.tc_sets))
    script_rev     = local.scope_tc_script_rev
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]

    command = <<-EOT
      set -euxo pipefail
      ${path.module}/scripts/scope_tc_attributes_sync.sh
    EOT

    environment = {
      KCADM_EXEC_MODE        = var.kcadm_exec_mode
      KCADM_PATH             = var.keycloak_kcadm_path
      KEYCLOAK_CONTAINER_NAME= var.keycloak_container_name
      KEYCLOAK_NAMESPACE     = var.keycloak_namespace
      KEYCLOAK_POD_SELECTOR  = var.keycloak_pod_selector
      KEYCLOAK_URL           = var.keycloak_url
      KEYCLOAK_AUTH_REALM    = var.keycloak_auth_realm
      KEYCLOAK_CLIENT_ID     = var.keycloak_client_id
      KEYCLOAK_CLIENT_SECRET = var.keycloak_client_secret
      REALM_ID               = var.realm_id
      SCOPE_ID               = self.triggers.scope_id
      SCOPE_KEY              = self.triggers.scope_key
      SCOPE_NAME             = self.triggers.scope_name
      TC_SETS_JSON           = self.triggers.tc_sets_json
      TC_PREFIX_ROOT         = "tc"
      SYNC_MODE              = "replace"
    }
  }


  depends_on = [
    keycloak_openid_client_scope.shared_scopes,
    keycloak_generic_protocol_mapper.shared,
  ]
}
