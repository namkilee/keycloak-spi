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

# =========================
# 운영 정책/보호장치 (추가)
# =========================
variable "tc_sync" {
  type = object({
    mode          = optional(string, "replace") # "replace" | "merge"
    allow_delete  = optional(bool, true)        # replace에서 삭제 허용 여부
    tc_prefix_root= optional(string, "tc")      # attribute prefix root
    dry_run       = optional(bool, false)
    max_retries   = optional(number, 5)
    backoff_ms    = optional(number, 400)
    script_rev    = optional(string, "rev-0.2")
  })
  default = {}
}

# =========================
# tc_sets 타입 정리 (title 포함)
# =========================
locals {
  tc_set_object = object({
    required = bool
    version  = string
    title    = optional(string)
    url      = optional(string)
    template = optional(string)
    # key는 굳이 중복 보관하지 않고 "map key"를 tc key로 사용 (권장)
  })
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

      tc_sets = optional(map(local.tc_set_object))
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

  # tc_sets[*]는 url/template 중 최소 1개는 있어야 한다 (운영 권장)
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
}

variable "shared_scopes" {
  type = map(object({
    description = optional(string, "")

    mappers = optional(list(object({
      name            = string
      protocol_mapper = string
      config          = map(string)
    })), [])

    tc_sets = optional(map(local.tc_set_object))
  }))

  default     = {}
  description = "Shared client scopes and their protocol mappers."

  validation {
    condition = alltrue(flatten([
      for scope_key, scope in var.shared_scopes : [
        for tc_key, tc in try(scope.tc_sets, {}) :
        (try(tc.url, "") != "" || try(tc.template, "") != "")
      ]
    ]))
    error_message = "shared_scopes[*].tc_sets[*] must have at least one of url or template."
  }
}
