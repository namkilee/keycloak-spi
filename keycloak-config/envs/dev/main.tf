terraform {
  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = ">= 4.0.0"
    }
  }
}

provider "keycloak" {
  url           = var.keycloak_url
  client_id     = var.keycloak_client_id
  client_secret = var.keycloak_client_secret
  realm         = var.keycloak_admin_realm
}

resource "keycloak_realm" "realm" {
  realm        = var.realm_name
  display_name = var.realm_display_name
  enabled      = true
}

module "client_scopes" {
  source = "../../modules/scopes"

  realm_id          = keycloak_realm.realm.id
  terms_scope_name  = "terms"
  claims_scope_name = "claims"

  terms_attributes = {
    "tc.required"              = "privacy,claims"
    "tc.term.privacy.title"    = "Privacy Policy"
    "tc.term.privacy.version"  = "v1"
    "tc.term.privacy.url"      = "https://example.com/privacy"
    "tc.term.claims.title"     = "Claims Processing"
    "tc.term.claims.version"   = "v1"
    "tc.term.claims.url"       = "https://example.com/claims"
  }

  mapper_name = "dept-transform"
  mapper_config = {
    "source.user.attribute"      = "dept_code"
    "target.claim.name"          = "dept"
    "mapping.inline"             = "A01:finance,A02:people"
    "mapping.client.autoKey"     = "true"
    "mapping.client.key"         = "dept.map"
    "fallback.original"          = "true"
    "source.user.attribute.multi" = "false"
    "access.token.claim"         = "true"
    "id.token.claim"             = "true"
    "userinfo.token.claim"       = "true"
    "claim.name"                 = "dept"
    "jsonType.label"             = "String"
  }
}

resource "keycloak_required_action" "terms_required" {
  realm_id    = keycloak_realm.realm.id
  alias       = "terms-required-action"
  name        = "Terms & Conditions (multi)"
  provider_id = "terms-required-action"
  enabled     = true
  default_action = false
}

resource "keycloak_openid_client" "app" {
  realm_id                     = keycloak_realm.realm.id
  client_id                    = var.client_id
  name                         = var.client_name
  enabled                      = true
  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = true
  direct_access_grants_enabled = true
  root_url                     = var.client_root_url
  base_url                     = var.client_root_url
  valid_redirect_uris          = var.client_redirect_uris
  web_origins                  = var.client_web_origins
}

resource "keycloak_openid_client_default_scopes" "app" {
  realm_id  = keycloak_realm.realm.id
  client_id = keycloak_openid_client.app.id
  default_scopes = [
    module.client_scopes.terms_name,
    module.client_scopes.claims_name,
  ]
}
