resource "keycloak_openid_client" "terraform" {
  realm_id = var.keycloak_admin_realm

  client_id = var.terraform_client_id
  name      = var.terraform_client_name
  enabled   = true

  access_type                  = "CONFIDENTIAL"
  service_accounts_enabled     = true
  standard_flow_enabled        = false
  direct_access_grants_enabled = false

  client_secret = var.client_secret_override
}

data "keycloak_openid_client_service_account_user" "sa" {
  realm_id  = var.keycloak_admin_realm
  client_id = keycloak_openid_client.terraform.id
}

data "keycloak_role" "realm_admin" {
  count    = var.assign_global_admin ? 1 : 0
  realm_id = var.keycloak_admin_realm
  name     = "admin"
}

resource "keycloak_user_realm_roles" "sa_realm_admin" {
  count    = var.assign_global_admin ? 1 : 0
  realm_id = var.keycloak_admin_realm
  user_id  = data.keycloak_openid_client_service_account_user.sa.id
  role_ids = [data.keycloak_role.realm_admin[0].id]
}

data "keycloak_openid_client" "realm_management" {
  count     = var.assign_global_admin ? 0 : 1
  realm_id  = var.keycloak_admin_realm
  client_id = "realm-management"
}

data "keycloak_role" "realm_mgmt_roles" {
  for_each = var.assign_global_admin ? toset([]) : toset(var.realm_management_roles)

  realm_id  = var.keycloak_admin_realm
  client_id = data.keycloak_openid_client.realm_management[0].id
  name      = each.value
}

resource "keycloak_openid_client_service_account_realm_role" "sa_realm_mgmt_roles" {
  count = var.assign_global_admin ? 0 : 1

  realm_id                = var.keycloak_admin_realm
  service_account_user_id = data.keycloak_openid_client_service_account_user.sa.id
  role_ids                = [for r in data.keycloak_role.realm_mgmt_roles : r.id]
}
