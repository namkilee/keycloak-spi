variable "realm_id" {
  type = string
}

variable "clients" {
  type = map(object({
    client_id        = string
    name             = string
    root_url         = string
    redirect_uris    = list(string)
    web_origins      = list(string)
    scopes = map(object({
      description = optional(string, "")
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
