locals {
  resolved_auth_realm = coalesce(
    var.keycloak_auth_realm,
    data.terraform_remote_state.bootstrap.outputs.bootstrap_realm_id
  )
}

module "realm_clients" {
  source = "../modules/realm-clients"

  realm_id = data.terraform_remote_state.bootstrap.outputs.bootstrap_realm_id

  clients = var.clients
  keycloak_url           = var.keycloak_url
  keycloak_auth_realm    = local.resolved_auth_realm
  keycloak_client_id     = coalesce(var.keycloak_client_id, data.terraform_remote_state.bootstrap.outputs.terraform_client_id)
  keycloak_client_secret = coalesce(var.keycloak_client_secret, data.terraform_remote_state.bootstrap.outputs.terraform_client_secret)
  kcadm_exec_mode        = "docker"
  keycloak_container_name = var.keycloak_container_name

  saml_idp_alias           = var.saml_idp_alias
  saml_idp_display_name    = var.saml_idp_display_name
  saml_entity_id           = var.saml_entity_id
  saml_idp_entity_id       = var.saml_idp_entity_id
  saml_sso_url             = var.saml_sso_url
  saml_slo_url             = var.saml_slo_url
  saml_signing_certificate = var.saml_signing_certificate
  saml_enabled             = var.saml_enabled
  saml_principal_type      = var.saml_principal_type
  saml_principal_attribute = var.saml_principal_attribute
  saml_idp_mappers         = var.saml_idp_mappers
}
