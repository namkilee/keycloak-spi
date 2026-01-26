# Keycloak Terraform Bootstrap

This module creates a new realm and bootstraps a Terraform service-account client in that realm.
Authentication still happens against the admin realm (default: `master`).

## Usage
1. Configure the backend so the bootstrap state is stored remotely (required for `envs/*`):
   - Edit `backend.tf` values to match your S3/MinIO backend.
```
terraform init
```

2. Apply:
```
terraform apply -var-file=terraform.tfvars
```

## Security
- Do NOT commit terraform.tfvars
- Protect bootstrap tfstate (contains secrets)
