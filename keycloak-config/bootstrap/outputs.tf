output "terraform_client_id" {
  value = keycloak_openid_client.terraform.client_id
}

output "bootstrap_realm_id" {
  description = "Realm id created for terraform bootstrap"
  value       = keycloak_realm.bootstrap.id
}

output "terraform_client_secret" {
  description = "Client secret for terraform client (treat as password)"
  value       = keycloak_openid_client.terraform.client_secret
  sensitive   = true
}

output "service_account_user_id" {
  description = "Service account user id for the terraform client"
  value       = keycloak_openid_client.terraform.service_account_user_id
}
