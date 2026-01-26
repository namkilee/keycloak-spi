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

module "client_scopes" {
  source = "../../modules/scopes"

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
  realm_id    = local.resolved_target_realm
  alias       = "terms-required-action"
  name        = "Terms & Conditions (multi)"
  provider_id = "terms-required-action"
  enabled     = true
  default_action = false
}

resource "keycloak_openid_client" "app" {
  for_each = var.clients

  realm_id                     = local.resolved_target_realm
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

  realm_id  = local.resolved_target_realm
  client_id = each.value.id
  default_scopes = [
    module.client_scopes.terms_name,
    module.client_scopes.claims_name,
  ]
}

resource "keycloak_saml_identity_provider" "saml_idp" {
  realm                     = local.resolved_target_realm
  alias                     = var.saml_idp_alias
  display_name              = var.saml_idp_display_name
  entity_id                 = var.saml_entity_id
  single_sign_on_service_url = var.saml_sso_url
  single_logout_service_url  = var.saml_slo_url
  signing_certificate       = var.saml_signing_certificate
  enabled                   = var.saml_enabled
  trust_email               = var.saml_trust_email
}
