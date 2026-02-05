output "approval_portal_client_id" {
  value = keycloak_openid_client.approval_portal.client_id
}

# ✅ secret output 제거 (state 접근 통제는 별도로 필수)
# output "approval_portal_client_secret" { ... }  <-- 없음

output "approval_portal_service_account_user_id" {
  value = keycloak_openid_client.approval_portal.service_account_user_id
}

output "service_clients" {
  value = {
    for k, c in keycloak_openid_client.app :
    k => {
      client_id    = c.client_id
      internal_id  = c.id
      auto_approve = try(var.clients[k].auto_approve, false)
    }
  }
}

output "service_approved_roles" {
  value = {
    for k, r in keycloak_role.approved :
    k => {
      name = r.name
      id   = r.id
    }
  }
}

output "saml_idp_alias" {
  value = keycloak_saml_identity_provider.saml_idp.alias
}

output "post_broker_approval_flow_alias" {
  value = keycloak_authentication_flow.post_broker_approval.alias
}
