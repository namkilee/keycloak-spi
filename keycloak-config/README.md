# Keycloak Terraform Config

This directory contains Terraform templates for provisioning Keycloak realms, clients, client scopes, and the custom value-transform mapper.
It is structured as a small environment layout (dev/stg/prd) that uses a MinIO (S3-compatible) backend.

## Structure

- `modules/scopes`: Creates the `terms` and `claims` client scopes, plus the `value-transform-protocol-mapper`.
- `envs/dev|stg|prd`: Environment-specific Terraform roots with MinIO backend configuration, realm + client creation, required action enablement, and default scope attachment.

## Usage

1. Copy the example variables and update them for your environment:

```
cd envs/dev
cp terraform.tfvars.example terraform.tfvars
```

2. Initialize Terraform:

```
terraform init
```

3. Apply:

```
terraform apply
```
