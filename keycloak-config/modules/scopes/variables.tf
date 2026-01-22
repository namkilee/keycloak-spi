variable "realm_id" {
  type = string
}

variable "terms_scope_name" {
  type    = string
  default = "terms"
}

variable "claims_scope_name" {
  type    = string
  default = "claims"
}

variable "terms_attributes" {
  type = map(string)
}

variable "mapper_name" {
  type    = string
  default = "value-transform"
}

variable "mapper_config" {
  type = map(string)
}
