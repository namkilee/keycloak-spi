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

# =========================
# TC Sync 운영 정책/보호장치
# =========================
variable "tc_sync" {
  type = object({
    mode           = optional(string, "replace") # replace | merge
    allow_delete   = optional(bool, true)
    tc_prefix_root = optional(string, "tc")
    dry_run        = optional(bool, false)

    max_retries = optional(number, 5)
    backoff_ms  = optional(number, 400)

    script_rev = optional(string, "rev-0.2")
  })
  default = {}

  validation {
    condition     = contains(["replace", "merge"], try(var.tc_sync.mode, "replace"))
    error_message = "tc_sync.mode must be one of: replace, merge."
  }
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9_-]*$", try(var.tc_sync.tc_prefix_root, "tc")))
    error_message = "tc_sync.tc_prefix_root must match ^[a-z0-9][a-z0-9_-]*$."
  }
  validation {
    condition     = try(var.tc_sync.max_retries, 5) >= 1 && try(var.tc_sync.max_retries, 5) <= 20
    error_message = "tc_sync.max_retries must be between 1 and 20."
  }
  validation {
    condition     = try(var.tc_sync.backoff_ms, 400) >= 100 && try(var.tc_sync.backoff_ms, 400) <= 5000
    error_message = "tc_sync.backoff_ms must be between 100 and 5000."
  }
}

# =========================
# Shared scopes
# =========================
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
      title    = optional(string)
      url      = optional(string)
      template = optional(string)
    })), {})
  }))

  default     = {}
  description = "Shared client scopes and their protocol mappers."

  validation {
    condition     = alltrue([for k in keys(var.shared_scopes) : can(regex("^[a-z0-9][a-z0-9_-]*$", k))])
    error_message = "shared_scopes keys must match ^[a-z0-9][a-z0-9_-]*$."
  }

  validation {
    condition = alltrue(flatten([
      for scope_key, scope in var.shared_scopes : [
        for tc_key, tc in try(scope.tc_sets, {}) :
        can(regex("^[a-z0-9][a-z0-9_-]*$", tc_key))
      ]
    ]))
    error_message = "shared_scopes[*].tc_sets keys must match ^[a-z0-9][a-z0-9_-]*$."
  }

  validation {
    condition = alltrue(flatten([
      for scope_key, scope in var.shared_scopes : [
        for tc_key, tc in try(scope.tc_sets, {}) :
        (try(tc.url, "") != "" || try(tc.template, "") != "")
      ]
    ]))
    error_message = "shared_scopes[*].tc_sets[*] must have at least one of url or template."
  }

  validation {
    condition = alltrue(flatten([
      for scope_key, scope in var.shared_scopes : [
        for tc_key, tc in try(scope.tc_sets, {}) : 
        can(regex("^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$", trimspace(tostring(tc.version))))
      ]
    ]))
    error_message = "shared_scopes[*].tc_sets[*].version must be a date in YYYY-MM-DD format."
  }
}

# =========================
# Clients
# =========================
variable "clients" {
  type = map(object({
    client_id     = string
    name          = string
    root_url      = string
    redirect_uris = list(string)
    web_origins   = list(string)
    access_type   = optional(string, "PUBLIC")
    standard_flow_enabled = optional(bool, false)
    direct_access_grants_enabled = optional(bool, false)
    pkce_code_challenge_method = optional(string, "S256")
    login_theme = optional(string, "aap")
    auto_approve = optional(bool, false)

    scopes = optional(map(object({
      description = optional(string, "")

      tc_sets = optional(map(object({
        required = bool
        version  = string
        title    = optional(string)
        url      = optional(string)
        template = optional(string)
      })), {})
    })), {})

    default_scopes = optional(list(string), [])

    mappers = optional(list(object({
      name            = string
      scope           = string
      protocol_mapper = string
      config          = map(string)
    })), [])
  }))

  description = "Map of client definitions used to create client-specific scopes and mappers."

  validation {
    condition     = alltrue([for k in keys(var.clients) : can(regex("^[a-z0-9][a-z0-9_-]*$", k))])
    error_message = "clients keys must match ^[a-z0-9][a-z0-9_-]*$."
  }

  validation {
    condition = alltrue(flatten([
      for client_key, c in var.clients : [
        for scope_key in keys(c.scopes) :
        can(regex("^[a-z0-9][a-z0-9_-]*$", scope_key))
      ]
    ]))
    error_message = "clients[*].scopes keys must match ^[a-z0-9][a-z0-9_-]*$."
  }

  validation {
    condition = alltrue(flatten([
      for client_key, c in var.clients : [
        for scope_key, scope in c.scopes : [
          for tc_key, tc in try(scope.tc_sets, {}) :
          can(regex("^[a-z0-9][a-z0-9_-]*$", tc_key))
        ]
      ]
    ]))
    error_message = "clients[*].scopes[*].tc_sets keys must match ^[a-z0-9][a-z0-9_-]*$."
  }

  validation {
    condition = alltrue(flatten([
      for client_key, c in var.clients : [
        for scope_key, scope in c.scopes : [
          for tc_key, tc in try(scope.tc_sets, {}) :
          (try(tc.url, "") != "" || try(tc.template, "") != "")
        ]
      ]
    ]))
    error_message = "clients[*].scopes[*].tc_sets[*] must have at least one of url or template."
  }

  validation {
    condition = alltrue(flatten([
      for client_key, c in var.clients : [
        for scope_key, scope in c.scopes : [
          for tc_key, tc in try(scope.tc_sets, {}) :
          can(regex("^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$", trimspace(tostring(tc.version))))
        ]
      ]
    ]))
    error_message = "clients[*].scopes[*].tc_sets[*].version must be a date in YYYY-MM-DD format."
  }

  validation {
    condition = alltrue(flatten([
      for client_key, c in var.clients : [
        for s in c.default_scopes :
        contains(keys(c.scopes), s) || contains(keys(var.shared_scopes), s)
      ]
    ]))
    error_message = "clients[*].default_scopes must contain only scope keys that exist in clients[*].scopes or shared_scopes."
  }

  validation {
    condition = alltrue(flatten([
      for client_key, c in var.clients : [
        for m in c.mappers : contains(keys(c.scopes), m.scope)
      ]
    ]))
    error_message = "clients[*].mappers[*].scope must reference an existing scope key in clients[*].scopes."
  }
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
