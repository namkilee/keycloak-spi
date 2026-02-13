variable "userinfosync_defaults" {
  type        = map(any)
  description = "Default userinfosync settings applied to realm attributes."
  default     = {}
}

variable "userinfosync_overrides" {
  type        = map(any)
  description = "Override values applied on top of defaults for the attributes output."
  default     = {}
}

variable "extra_realm_attributes" {
  type        = map(string)
  description = "Additional realm attributes to merge alongside userinfosync keys."
  default     = {}
}
