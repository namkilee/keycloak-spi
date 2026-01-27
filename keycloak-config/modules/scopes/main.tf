locals {
  client_scopes = {
    for item in flatten([
      for client_key, client in var.clients : [
        for scope_key, scope in client.scopes : {
          key        = "${client_key}.${scope_key}"
          client_key = client_key
          client_id  = client.client_id
          scope_key  = scope_key
          description = scope.description
        }
      ]
    ]) : item.key => item
  }

  client_mappers = {
    for item in flatten([
      for client_key, client in var.clients : [
        for mapper in client.mappers : {
          key                 = "${client_key}.${mapper.name}"
          client_key          = client_key
          scope_resource_key  = "${client_key}.${mapper.scope}"
          name                = mapper.name
          protocol_mapper     = mapper.protocol_mapper
          config              = mapper.config
        }
      ]
    ]) : item.key => item
  }

  terms_scope_attributes = {
    for item in flatten([
      for client_key, client in var.clients : [
        for scope_key, scope in client.scopes : {
          key         = "${client_key}.${scope_key}"
          client_key  = client_key
          client_id   = client.client_id
          scope_key   = scope_key
          attributes  = try(scope.terms_attributes, null)
        }
      ]
    ]) : item.key => item
    if item.scope_key == "terms" && item.attributes != null
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

resource "keycloak_generic_protocol_mapper" "value_transform" {
  for_each = local.client_mappers

  realm_id         = var.realm_id
  client_scope_id  = keycloak_openid_client_scope.scopes[each.value.scope_resource_key].id
  name             = each.value.name
  protocol         = "openid-connect"
  protocol_mapper  = each.value.protocol_mapper
  config           = each.value.config
}

resource "null_resource" "terms_scope_attributes" {
  for_each = local.terms_scope_attributes

  triggers = {
    scope_id    = keycloak_openid_client_scope.scopes[each.key].id
    tc_required = tostring(each.value.attributes.required)
    tc_version  = each.value.attributes.version
    tc_url      = coalesce(each.value.attributes.url, "")
    tc_template = coalesce(each.value.attributes.template, "")
    tc_key      = coalesce(each.value.attributes.key, "")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command = "${path.module}/scripts/terms_scope_attributes.sh"
    environment = {
      KCADM_EXEC_MODE        = var.kcadm_exec_mode
      KCADM_PATH             = var.keycloak_kcadm_path
      KEYCLOAK_CONTAINER_NAME = var.keycloak_container_name
      KEYCLOAK_NAMESPACE     = var.keycloak_namespace
      KEYCLOAK_POD_SELECTOR  = var.keycloak_pod_selector
      KEYCLOAK_URL           = var.keycloak_url
      KEYCLOAK_AUTH_REALM    = var.keycloak_auth_realm
      KEYCLOAK_CLIENT_ID     = var.keycloak_client_id
      KEYCLOAK_CLIENT_SECRET = var.keycloak_client_secret
      REALM_ID               = var.realm_id
      SCOPE_ID               = self.triggers.scope_id
      TC_REQUIRED            = self.triggers.tc_required
      TC_VERSION             = self.triggers.tc_version
      TC_URL                 = self.triggers.tc_url
      TC_TEMPLATE            = self.triggers.tc_template
      TC_KEY                 = self.triggers.tc_key
    }
  }

  depends_on = [keycloak_openid_client_scope.scopes]
}
