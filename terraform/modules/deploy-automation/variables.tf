variable "name" {
  description = "Name prefix for the Lambda, IAM role and EventBridge rule."
  type        = string
}

variable "codedeploy_app_name" {
  description = "CodeDeploy application that owns the deployment groups."
  type        = string
}

variable "codedeploy_app_arn" {
  description = "ARN of the CodeDeploy application."
  type        = string
}

variable "deployment_config_arn" {
  description = "ARN of the CodeDeploy deployment configuration used by the groups."
  type        = string
}

variable "services" {
  description = "Services deployed by the automation, keyed by service name."
  type = map(object({
    parameter_name         = string # SSM parameter holding the image tag
    repository_name        = string
    repository_arn         = string
    repository_url         = string
    task_definition_family = string
    container_name         = string
    container_port         = number
    deployment_group_name  = string
    deployment_group_arn   = string
    pass_role_arns         = list(string)
  }))
}

variable "log_retention_days" {
  description = "Retention of the Lambda log group."
  type        = number
  default     = 30
}
