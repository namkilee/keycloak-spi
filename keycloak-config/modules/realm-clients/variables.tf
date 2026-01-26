variable "realm_id" {
  type = string
}

variable "terms_scope_name" {
  type = string
}

variable "claims_scope_name" {
  type = string
}

variable "terms_attributes" {
  type = map(string)
}

variable "mapper_name" {
  type = string
}

variable "mapper_config" {
  type = map(string)
}

variable "clients" {
  type = map(object({
    client_id     = string
    name          = string
    root_url      = string
    redirect_uris = list(string)
    web_origins   = list(string)
  }))
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
