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

variable "approval_portal_url" {
  type        = string
  description = "Approval portal base URL used in Keycloak approval pending UI"
}

variable "keycloak_namespace" {
  type = string
}

variable "keycloak_pod_selector" {
  type = string
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
    login_theme      = optional(string, "AAP")
    scopes = map(object({
      description = optional(string, "")
      terms_attributes = optional(object({
        required = bool
        version  = string
        url      = optional(string)
        template = optional(string)
        key      = optional(string)
      }))
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

  # default_scopes 안의 값이 scopes 또는 shared_scopes의 key로 존재하는지 검증
  validation {
    condition = alltrue(flatten([
      for client_key, c in var.clients : [
        for s in c.default_scopes : contains(keys(c.scopes), s) || contains(keys(var.shared_scopes), s)
      ]
    ]))
    error_message = "clients[*].default_scopes must contain only scope keys that exist in clients[*].scopes or shared_scopes."
  }

  # mappers[*].scope 가 scopes map의 key로 존재하는지 검증
  validation {
    condition = alltrue(flatten([
      for client_key, c in var.clients : [
        for m in c.mappers : contains(keys(c.scopes), m.scope)
      ]
    ]))
    error_message = "clients[*].mappers[*].scope must reference an existing scope key in clients[*].scopes."
  }

}

variable "shared_scopes" {
  type = map(object({
    description = optional(string, "")

    mappers = optional(list(object({
      name            = string
      protocol_mapper = string
      config          = map(string)
    })), [])

    tc_sets = optional(map(object({
      required = bool
      version  = string
      url      = optional(string)
      template = optional(string)
      key      = optional(string)
    })))
  }))

  default     = {}
  description = "Shared client scopes and their protocol mappers."
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

variable "saml_idp_mappers" {
  type = list(object({
    name            = string
    type            = string
    attribute_name  = optional(string)
    attribute_friendly_name = optional(string)
    claim_name      = optional(string)
    claim_value     = optional(string)
    user_attribute  = optional(string)
    attribute_value = optional(string)
    role            = optional(string)
    group           = optional(string)
    user_session    = optional(bool)
    identity_provider_mapper = optional(string)
    config          = optional(map(string))
    extra_config    = optional(map(string))
    sync_mode       = optional(string, "INHERIT")
  }))
  default = []

  validation {
    condition = alltrue([
      for mapper in var.saml_idp_mappers : contains([
        "attribute_importer",
        "hardcoded_attribute",
        "attribute_to_role",
        "custom",
        "hardcoded_group",
        "hardcoded_role",
      ], mapper.type)
    ])
    error_message = "saml_idp_mappers[*].type must be one of attribute_importer, hardcoded_attribute, attribute_to_role, hardcoded_group, hardcoded_role, custom."
  }

  validation {
    condition = alltrue([
      for mapper in var.saml_idp_mappers : (
        mapper.type == "attribute_importer" ? (
          mapper.user_attribute != null && (
            mapper.attribute_name != null ||
            mapper.attribute_friendly_name != null ||
            mapper.claim_name != null
          )
        ) : mapper.type == "hardcoded_attribute" ? (
          mapper.attribute_name != null && mapper.attribute_value != null && mapper.user_session != null
        ) : mapper.type == "attribute_to_role" ? (
          mapper.role != null && (
            mapper.attribute_name != null ||
            mapper.attribute_friendly_name != null ||
            mapper.claim_name != null
          )
        ) : mapper.type == "hardcoded_group" ? (
          mapper.group != null
        ) : mapper.type == "hardcoded_role" ? (
          mapper.role != null
        ) : (
          mapper.identity_provider_mapper != null
        )
      )
    ])
    error_message = "saml_idp_mappers entries must provide required fields for their type."
  }
}
