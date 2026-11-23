variable "name" {
  description = "Name prefix for the IAM role."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the role, as owner/name."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like owner/name."
  }
}

variable "allowed_refs" {
  description = "Git refs allowed to assume the role (matched against the OIDC sub claim)."
  type        = list(string)
  default     = ["refs/heads/main"]
}

variable "ecr_repository_arns" {
  description = "ECR repositories the workflow may push to."
  type        = list(string)
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false if the account already has one."
  type        = bool
  default     = true
}
