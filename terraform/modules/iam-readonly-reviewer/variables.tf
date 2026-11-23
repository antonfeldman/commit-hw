variable "user_name" {
  description = "Name of the read-only IAM user."
  type        = string
}

variable "require_mfa" {
  description = "Deny all actions until the user has signed in with MFA."
  type        = bool
  default     = true
}
