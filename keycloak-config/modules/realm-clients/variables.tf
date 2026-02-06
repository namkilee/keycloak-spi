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

# 추가: 승인 포털 URL (Required Action 화면에서 안내 링크로 사용)
variable "approval_portal_url" {
  type        = string
  description = "Approval portal base URL used in Keycloak approval pending UI"
}

variable "clients" {
  type = map(object({
    client_id     = string
    name          = string
    root_url      = string
    redirect_uris = list(string)
    web_origins   = list(string)
    login_theme   = optional(string)

    # client settings
    access_type                  = optional(string, "PUBLIC")
    standard_flow_enabled        = optional(bool, true)
    direct_access_grants_enabled = optional(bool, false)
    pkce_code_challenge_method   = optional(string, "S256")

    # 추가: 서비스별 자동 승인 정책
    auto_approve = optional(bool, false)

    scopes = map(object({
      description = optional(string, "")

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

variable "saml_idp_entity_id" {
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

variable "saml_name_id_policy_format" {
  type    = string
  default = "Unspecified"

  validation {
    condition = contains([
      "Email", "Kerberos", "X.509 Subject Name", "Unspecified",
      "Transient", "Windows Domain Qualified Name", "Persistent"
    ], var.saml_name_id_policy_format)
    error_message = "Invalid saml_name_id_policy_format."
  }
}

variable "saml_idp_mappers" {
  type = list(object({
    name                   = string
    type                   = string
    attribute_name         = optional(string)
    attribute_friendly_name = optional(string)
    claim_name             = optional(string)
    claim_value            = optional(string)
    user_attribute         = optional(string)
    attribute_value        = optional(string)
    role                   = optional(string)
    group                  = optional(string)
    user_session           = optional(bool)
    identity_provider_mapper = optional(string)
    config                 = optional(map(string))
    extra_config           = optional(map(string))
    sync_mode              = optional(string, "INHERIT")
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
