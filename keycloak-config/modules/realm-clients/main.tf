module "client_scopes" {
  source = "../scopes"

  realm_id = var.realm_id
  clients  = var.clients
}

resource "keycloak_required_action" "terms_required" {
  realm_id        = var.realm_id
  alias           = "terms-required-action"
  name            = "Terms & Conditions (multi)"
  provider_id     = "terms-required-action"
  enabled         = true
  default_action  = false
}

resource "keycloak_openid_client" "app" {
  for_each = var.clients

  realm_id                     = var.realm_id
  client_id                    = each.value.client_id
  name                         = each.value.name
  enabled                      = true
  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = true
  direct_access_grants_enabled = true
  root_url                     = each.value.root_url
  base_url                     = each.value.root_url
  valid_redirect_uris          = each.value.redirect_uris
  web_origins                  = each.value.web_origins
}

resource "keycloak_openid_client_default_scopes" "app" {
  for_each = keycloak_openid_client.app

  realm_id  = var.realm_id
  client_id = each.value.id
  default_scopes = [
    for scope_key in each.value.default_scopes :
    module.client_scopes.scope_names[each.key][scope_key]
  ]
  depends_on = [module.client_scopes]
}

resource "keycloak_saml_identity_provider" "saml_idp" {
  realm                      = var.realm_id
  alias                      = var.saml_idp_alias
  display_name               = var.saml_idp_display_name
  entity_id                  = var.saml_entity_id
  single_sign_on_service_url = var.saml_sso_url
  single_logout_service_url  = var.saml_slo_url
  signing_certificate        = var.saml_signing_certificate
  enabled                    = var.saml_enabled
  trust_email                = var.saml_trust_email
}
