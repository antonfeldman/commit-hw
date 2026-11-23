variable "name" {
  description = "Name prefix for the secret and KMS alias."
  type        = string
}

variable "domain_name" {
  description = "Domain the certificate is issued for (CN and first SAN)."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", var.domain_name))
    error_message = "domain_name must be a lowercase DNS name such as anton.com."
  }
}

variable "subject_alternative_names" {
  description = "Additional DNS names in the certificate."
  type        = list(string)
  default     = []
}

variable "organization" {
  description = "Organization (O) in the certificate subject."
  type        = string
  default     = "Commit home assignment"
}

variable "validity_period_hours" {
  description = "Certificate lifetime in hours (default 1 year)."
  type        = number
  default     = 8760
}

variable "early_renewal_hours" {
  description = "Terraform regenerates the certificate this many hours before it expires (on the next apply)."
  type        = number
  default     = 720
}

variable "secret_recovery_window_days" {
  description = "Days a deleted secret can be restored (0 = delete immediately, 7-30 otherwise)."
  type        = number
  default     = 7

  validation {
    condition     = var.secret_recovery_window_days == 0 || (var.secret_recovery_window_days >= 7 && var.secret_recovery_window_days <= 30)
    error_message = "secret_recovery_window_days must be 0 or between 7 and 30."
  }
}
