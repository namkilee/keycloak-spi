variable "realm_id" {
  type = string
}

variable "keycloak_url" {
  type = string
}

variable "keycloak_auth_realm" {
  type = string
}

variable "keycloak_client_id" {
  type = string
}

variable "keycloak_client_secret" {
  type      = string
  sensitive = true
}

variable "kcadm_exec_mode" {
  type = string
}

variable "keycloak_kcadm_path" {
  type    = string
  default = "/opt/bitnami/keycloak/bin/kcadm.sh"
}

variable "keycloak_container_name" {
  type    = string
  default = null
}

variable "keycloak_namespace" {
  type    = string
  default = null
}

variable "keycloak_pod_selector" {
  type    = string
  default = null
}

variable "clients" {
  type = map(object({
    client_id     = string
    name          = string
    root_url      = string
    redirect_uris = list(string)
    web_origins   = list(string)

    scopes = map(object({
      description = optional(string, "")

      # ✅ scope별 prefix(tc.<scope>.*)로 확장 가능한 다중 세트
      tc_sets = optional(map(object({
        required = bool
        version  = string
        url      = optional(string)
        template = optional(string)
        key      = optional(string)
      })))
    }))

    default_scopes = list(string)

    mappers = list(object({
      name            = string
      scope           = string
      protocol_mapper = string
      config          = map(string)
    }))
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

variable "saml_principal_type" {
  type = string
}

variable "saml_principal_attribute" {
  type = string
}
