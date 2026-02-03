# Keycloak Terraform Config

This directory contains Terraform templates for provisioning Keycloak realms, clients, client scopes, and the custom value-transform mapper.
It is structured as a small environment layout (dev/stg/prd) that uses a MinIO (S3-compatible) backend.

## Structure

- `modules/scopes`: Creates the `terms` and `claims` client scopes, plus the `value-transform-protocol-mapper`.
- `dev|stg|prd`: Environment-specific Terraform roots with MinIO backend configuration, client/IdP configuration applied to an existing realm, required action enablement, and default scope attachment. These envs read the bootstrap state to discover the realm id.
- `bootstrap`: Creates the Keycloak realm and service account client; realm attributes (including UserInfoSync) are managed here.

## UserInfoSync realm attributes

UserInfoSync attributes are managed via the `modules/realms-userinfosync` module in `bootstrap` so the realm settings live with realm creation. Configure defaults (and optional overrides) with `userinfosync_defaults` / `userinfosync_overrides` in `bootstrap/terraform.tfvars`. The `userinfosync.mappingJson` value is stored as a JSON string (use `jsonencode(...)`), and `userinfosync.invalidateOnKeys` is a comma-separated string. Keep Knox credentials in environment or secret management; do not store them in Terraform variables.

## Client scope attributes

Keycloak does not expose a separate “client scope attribute” object in the
provider, so the `terms` scope attributes are applied via `kcadm.sh` with a
`null_resource` provisioner. Supply the attributes under
`clients[*].scopes.terms.terms_attributes`, and they are written to
`attributes.tc.*` on the client scope without adding protocol mappers to tokens.
Other token-mapped values should continue to use protocol mappers.

The provisioner shells out to the Keycloak container:

- **dev** uses `docker exec` and requires `keycloak_container_name`.
- **stg/prd** uses `kubectl exec` and requires `keycloak_namespace` and
  `keycloak_pod_selector` (for example,
  `app.kubernetes.io/name=keycloak`).

## Usage

1. Copy the example variables and update them for your environment:

```
cd dev
cp terraform.tfvars.example terraform.tfvars
```

2. Initialize Terraform:

```
terraform init
```

> Note: `dev|stg|prd` reads the bootstrap state via the S3/MinIO backend configured in each
> environment. Terraform does not support “check local state first, then S3” fallback
> for `terraform_remote_state`, so the bootstrap state must be present in the configured
> backend (or the configuration must be changed to use a local backend explicitly).

3. Apply:

```
terraform apply
```
