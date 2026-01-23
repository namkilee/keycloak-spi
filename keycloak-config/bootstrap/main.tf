resource "keycloak_openid_client" "terraform" {
  realm_id = var.keycloak_admin_realm

  client_id = var.terraform_client_id
  name      = var.terraform_client_name
  enabled   = true

  access_type              = "CONFIDENTIAL"
  service_accounts_enabled = true

  standard_flow_enabled        = false
  direct_access_grants_enabled = false

  # (선택) 고정 secret을 쓰고 싶을 때만 사용
  client_secret = var.client_secret_override
}

# built-in realm-management client 조회
data "keycloak_openid_client" "realm_management" {
  realm_id  = var.keycloak_admin_realm
  client_id = "realm-management"
}

# Service Account에 client role 부여 (공식 provider 방식)
resource "keycloak_openid_client_service_account_role" "sa_roles" {
  for_each = toset(
    var.assign_global_admin
    ? ["realm-admin"]                # 강력 권한(관리자급) - 필요 시 조정
    : var.realm_management_roles
  )

  realm_id                = var.keycloak_admin_realm
  client_id               = data.keycloak_openid_client.realm_management.id
  service_account_user_id = keycloak_openid_client.terraform.service_account_user_id

  role = each.value
}
