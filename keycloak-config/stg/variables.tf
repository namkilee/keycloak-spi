variable "keycloak_url" {
  type = string
}

variable "keycloak_auth_realm" {
  type    = string
  default = null
}

variable "keycloak_client_id" {
  type    = string
  default = null
}

variable "keycloak_client_secret" {
  type      = string
  default   = null
  sensitive = true
}

variable "bootstrap_state_bucket" {
  type = string
}

variable "bootstrap_state_key" {
  type = string
}

variable "bootstrap_state_region" {
  type = string
}

variable "bootstrap_state_endpoint" {
  type = string
}

variable "bootstrap_state_access_key" {
  type      = string
  sensitive = true
}

variable "bootstrap_state_secret_key" {
  type      = string
  sensitive = true
}

variable "clients" {
  type = map(object({
    client_id        = string
    name             = string
    root_url         = string
    redirect_uris    = list(string)
    web_origins      = list(string)
    scopes = map(object({
      description = optional(string, "")
    }))
    default_scopes = list(string)
    mappers = list(object({
      name            = string
      scope           = string
      protocol_mapper = string
      config          = map(string)
    }))
  }))
  description = "Map of client definitions to provision in the target realm."
}

variable "saml_idp_alias" {
  type = string
}

variable "saml_idp_display_name" {
  type = string
}

variable "saml_entity_id" {
  type = string
}

variable "saml_sso_url" {
  type = string
}

variable "saml_slo_url" {
  type = string
}

variable "saml_signing_certificate" {
  type = string
}

variable "saml_enabled" {
  type = bool
}

variable "saml_principal_type" {
  type = string
}

variable "saml_principal_attribute" {
  type = string
}
