variable "keycloak_url" {
  type = string
}

variable "keycloak_auth_realm" {
  type    = string
  default = null
}

variable "keycloak_client_id" {
  type = string
}

variable "keycloak_client_secret" {
  type = string
  sensitive = true
}

variable "target_realm" {
  type    = string
  default = null
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

variable "client_id" {
  type = string
}

variable "client_name" {
  type = string
}

variable "client_root_url" {
  type = string
}

variable "client_redirect_uris" {
  type = list(string)
}

variable "client_web_origins" {
  type = list(string)
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

variable "saml_trust_email" {
  type = bool
}
