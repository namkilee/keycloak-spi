resource "keycloak_openid_client_scope" "terms" {
  realm_id               = var.realm_id
  name                   = var.terms_scope_name
  description            = "Terms and conditions"
  consent_screen_text    = "Terms"
  include_in_token_scope = true
  attributes             = var.terms_attributes
}

resource "keycloak_openid_client_scope" "claims" {
  realm_id               = var.realm_id
  name                   = var.claims_scope_name
  description            = "Custom claims"
  include_in_token_scope = true
}

resource "keycloak_generic_protocol_mapper" "value_transform" {
  realm_id         = var.realm_id
  client_scope_id  = keycloak_openid_client_scope.claims.id
  name             = var.mapper_name
  protocol         = "openid-connect"
  protocol_mapper  = "value-transform-protocol-mapper"
  config           = var.mapper_config
}
