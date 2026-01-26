# Keycloak Terraform Config

This directory contains Terraform templates for provisioning Keycloak realms, clients, client scopes, and the custom value-transform mapper.
It is structured as a small environment layout (dev/stg/prd) that uses a MinIO (S3-compatible) backend.

## Structure

- `modules/scopes`: Creates the `terms` and `claims` client scopes, plus the `value-transform-protocol-mapper`.
- `envs/dev|stg|prd`: Environment-specific Terraform roots with MinIO backend configuration, client/IdP configuration applied to an existing realm, required action enablement, and default scope attachment. These envs read the bootstrap state to discover the realm id.

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

> Note: `envs/*` reads the bootstrap state via the S3/MinIO backend configured in each
> environment. Terraform does not support “check local state first, then S3” fallback
> for `terraform_remote_state`, so the bootstrap state must be present in the configured
> backend (or the configuration must be changed to use a local backend explicitly).

3. Apply:

```
terraform apply
```
