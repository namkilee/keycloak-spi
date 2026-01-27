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

      # scope별 다중 약관/동의 세트 (삭제 포함 동기화 대상)
      # 예: tc_sets = { privacy = { required=true, version="..." }, tos = {...} }
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
}
