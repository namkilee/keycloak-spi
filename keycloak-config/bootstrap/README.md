# Keycloak Terraform Bootstrap

This module bootstraps a Terraform service-account client in Keycloak.

## Usage
terraform init
terraform apply -var-file=terraform.tfvars

## Security
- Do NOT commit terraform.tfvars
- Protect bootstrap tfstate (contains secrets)
