provider "keycloak" {
  url       = var.keycloak_url
  realm     = var.keycloak_admin_realm
  client_id = "admin-cli"

  username  = var.keycloak_admin_username
  password  = var.keycloak_admin_password
}
