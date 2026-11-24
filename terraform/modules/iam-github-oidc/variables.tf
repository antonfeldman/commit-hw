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

variable "oidc_subject_prefix" {
  description = <<-EOT
    Prefix of the OIDC token 'sub' claim, as shown by
    `gh api repos/<owner>/<repo>/actions/oidc/customization/sub` (sub_claim_prefix).
    Repos using GitHub's immutable subject format look like
    "repo:owner@<owner_id>/name@<repo_id>". null = classic "repo:owner/name".
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.oidc_subject_prefix == null || startswith(coalesce(var.oidc_subject_prefix, "x"), "repo:")
    error_message = "oidc_subject_prefix must start with 'repo:'."
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

variable "enable_deploy_permissions" {
  description = "Allow the workflow to register task definition revisions and start CodeDeploy deployments."
  type        = bool
  default     = false
}

variable "task_definition_families" {
  description = "Task definition families the workflow may register revisions of."
  type        = list(string)
  default     = []
}

variable "pass_role_arns" {
  description = "Task and execution roles the workflow may pass to ECS."
  type        = list(string)
  default     = []
}

variable "codedeploy_app_arn" {
  description = "CodeDeploy application that owns the deployment groups."
  type        = string
  default     = null
}

variable "deployment_config_arn" {
  description = "CodeDeploy deployment configuration used by the groups."
  type        = string
  default     = null
}

variable "deployment_group_arns" {
  description = "CodeDeploy deployment groups the workflow may start and read deployments of."
  type        = list(string)
  default     = []
}
