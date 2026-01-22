variable "keycloak_url" {
  type = string
}

variable "keycloak_admin_realm" {
  type = string
}

variable "keycloak_client_id" {
  type = string
}

variable "keycloak_client_secret" {
  type = string
  sensitive = true
}

variable "realm_name" {
  type = string
}

variable "realm_display_name" {
  type = string
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
