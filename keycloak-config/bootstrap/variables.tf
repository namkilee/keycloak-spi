variable "keycloak_url" {
  description = "Keycloak base URL (e.g., https://keycloak.example.com)"
  type        = string
}

variable "keycloak_admin_realm" {
  description = "Admin realm to authenticate against. Usually 'master'."
  type        = string
  default     = "master"
}

variable "bootstrap_realm_name" {
  description = "New realm name to create for Terraform-managed resources"
  type        = string
}

variable "bootstrap_realm_display_name" {
  description = "Display name for the new realm"
  type        = string
  default     = null
}

variable "keycloak_admin_username" {
  description = "Bootstrap admin username"
  type        = string
  sensitive   = true
}

variable "keycloak_admin_password" {
  description = "Bootstrap admin password"
  type        = string
  sensitive   = true
}

variable "terraform_client_id" {
  description = "Client ID for terraform service account client"
  type        = string
  default     = "terraform"
}

variable "terraform_client_name" {
  description = "Client display name"
  type        = string
  default     = "Terraform Provisioner"
}

variable "assign_global_admin" {
  description = "Assign full admin role to service account"
  type        = bool
  default     = false
}

variable "realm_management_roles" {
  description = "realm-management client roles to assign"
  type        = list(string)
  default     = [
    "view-realm",
    "manage-clients",
    "manage-users",
    "manage-identity-providers",
    "manage-realm",
  ]
}

variable "client_secret_override" {
  description = "Optional fixed client secret"
  type        = string
  default     = null
  sensitive   = true
}

variable "userinfosync_defaults" {
  description = "Default UserInfoSync realm attribute settings."
  type        = map(any)
  default     = {}
}

variable "userinfosync_overrides" {
  description = "Override UserInfoSync realm attribute settings."
  type        = map(any)
  default     = {}
}

variable "extra_realm_attributes" {
  description = "Additional realm attributes to apply to the bootstrap realm."
  type        = map(string)
  default     = {}
}
