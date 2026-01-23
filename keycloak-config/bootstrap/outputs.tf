output "terraform_client_id" {
  value = keycloak_openid_client.terraform.client_id
}

output "terraform_client_secret" {
  value     = keycloak_openid_client.terraform.client_secret
  sensitive = true
}

output "service_account_user_id" {
  value = data.keycloak_openid_client_service_account_user.sa.id
}
