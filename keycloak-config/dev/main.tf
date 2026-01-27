terraform {
  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = "~> 5.4"
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
  resolved_auth_realm = coalesce(
    var.keycloak_auth_realm,
    data.terraform_remote_state.bootstrap.outputs.bootstrap_realm_id
  )
}

provider "keycloak" {
  url           = var.keycloak_url
  client_id     = coalesce(var.keycloak_client_id, data.terraform_remote_state.bootstrap.outputs.terraform_client_id)
  client_secret = coalesce(var.keycloak_client_secret, data.terraform_remote_state.bootstrap.outputs.terraform_client_secret)
  realm         = local.resolved_auth_realm
}

module "realm_clients" {
  source = "../modules/realm-clients"

  realm_id          = data.terraform_remote_state.bootstrap.outputs.bootstrap_realm_id

  clients = var.clients

  saml_idp_alias           = var.saml_idp_alias
  saml_idp_display_name    = var.saml_idp_display_name
  saml_entity_id           = var.saml_entity_id
  saml_sso_url             = var.saml_sso_url
  saml_slo_url             = var.saml_slo_url
  saml_signing_certificate = var.saml_signing_certificate
  saml_enabled             = var.saml_enabled
  saml_principal_type      = var.saml_principal_type
  saml_principal_attribute = var.saml_principal_attribute
}
