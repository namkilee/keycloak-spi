provider "keycloak" {
  url           = var.keycloak_url
  client_id     = coalesce(var.keycloak_client_id, data.terraform_remote_state.bootstrap.outputs.terraform_client_id)
  client_secret = coalesce(var.keycloak_client_secret, data.terraform_remote_state.bootstrap.outputs.terraform_client_secret)
  realm         = local.resolved_auth_realm

  root_ca_certificate = file("${path.module}/../ca.pem")
}
