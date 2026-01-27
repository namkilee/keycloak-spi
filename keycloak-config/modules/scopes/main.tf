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
