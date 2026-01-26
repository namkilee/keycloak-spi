# Keycloak Terraform Bootstrap

This module creates a new realm and bootstraps a Terraform service-account client in that realm.
Authentication still happens against the admin realm (default: `master`).

## Usage
terraform init
terraform apply -var-file=terraform.tfvars

## Security
- Do NOT commit terraform.tfvars
- Protect bootstrap tfstate (contains secrets)
