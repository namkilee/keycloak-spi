terraform {
  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = ">= 4.0.0"
    }
  }
}

data "terraform_remote_state" "bootstrap" {
  backend = "s3"
  config = {
    bucket                      = var.bootstrap_state_bucket
    key                         = var.bootstrap_state_key
    region                      = var.bootstrap_state_region
    endpoint                    = var.bootstrap_state_endpoint
    access_key                  = var.bootstrap_state_access_key
    secret_key                  = var.bootstrap_state_secret_key
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    force_path_style            = true
  }
}

locals {
  resolved_target_realm = coalesce(var.target_realm, data.terraform_remote_state.bootstrap.outputs.bootstrap_realm_id)
  resolved_auth_realm   = coalesce(var.keycloak_auth_realm, local.resolved_target_realm)
}

provider "keycloak" {
  url           = var.keycloak_url
  client_id     = var.keycloak_client_id
  client_secret = var.keycloak_client_secret
  realm         = local.resolved_auth_realm
}

module "realm_clients" {
  source = "../../modules/realm-clients"

  realm_id          = local.resolved_target_realm
  terms_scope_name  = "terms"
  claims_scope_name = "claims"
  terms_attributes = {
    "tc.required"              = "privacy,claims"
    "tc.term.privacy.title"    = "Privacy Policy"
    "tc.term.privacy.version"  = "v1"
    "tc.term.privacy.url"      = "https://example.com/privacy"
    "tc.term.privacy.required" = "true"
    "tc.term.claims.title"     = "Claims Processing"
    "tc.term.claims.version"   = "v1"
    "tc.term.claims.url"       = "https://example.com/claims"
    "tc.term.claims.required"  = "true"
  }
  mapper_name   = "dept-transform"
  mapper_config = {
    "source.user.attribute"       = "dept_code"
    "target.claim.name"           = "dept"
    "mapping.inline"              = "A01:finance,A02:people"
    "mapping.client.autoKey"      = "true"
    "mapping.client.key"          = "dept.map"
    "fallback.original"           = "true"
    "source.user.attribute.multi" = "false"
    "access.token.claim"          = "true"
    "id.token.claim"              = "true"
    "userinfo.token.claim"        = "true"
    "claim.name"                  = "dept"
    "jsonType.label"              = "String"
  }

  clients = var.clients

  saml_idp_alias           = var.saml_idp_alias
  saml_idp_display_name    = var.saml_idp_display_name
  saml_entity_id           = var.saml_entity_id
  saml_sso_url             = var.saml_sso_url
  saml_slo_url             = var.saml_slo_url
  saml_signing_certificate = var.saml_signing_certificate
  saml_enabled             = var.saml_enabled
  saml_trust_email         = var.saml_trust_email
}
