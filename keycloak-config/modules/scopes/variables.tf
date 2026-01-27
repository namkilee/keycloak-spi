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
  type        = string
  description = "How to execute kcadm.sh: docker or kubectl."
}

variable "keycloak_kcadm_path" {
  type        = string
  description = "Path to kcadm.sh inside the Keycloak container."
  default     = "/opt/bitnami/keycloak/bin/kcadm.sh"
}

variable "keycloak_container_name" {
  type        = string
  description = "Docker container name for Keycloak (dev only)."
  default     = null
}

variable "keycloak_namespace" {
  type        = string
  description = "Kubernetes namespace for Keycloak (stg/prd only)."
  default     = null
}

variable "keycloak_pod_selector" {
  type        = string
  description = "Label selector for the Keycloak pod (stg/prd only)."
  default     = null
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

  description = "Map of client definitions used to create client-specific scopes and mappers."

  # default_scopes 안의 값이 scopes map의 key로 존재하는지 검증
  validation {
    condition = alltrue(flatten([
      for client_key, c in var.clients : [
        for s in c.default_scopes : contains(keys(c.scopes), s)
      ]
    ]))
    error_message = "clients[*].default_scopes must contain only scope keys that exist in clients[*].scopes. Check each client's default_scopes vs scopes map keys."
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
