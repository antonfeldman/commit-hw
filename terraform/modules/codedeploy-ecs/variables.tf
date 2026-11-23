variable "name" {
  description = "Name of the CodeDeploy application (also the IAM role / alarm name prefix)."
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster that runs the services."
  type        = string
}

variable "services" {
  description = "Blue/green services, keyed by deployment group name."
  type = map(object({
    service_name            = string
    production_listener_arn = string
    target_group_names      = map(string) # { blue = "...", green = "..." }
    alb_arn_suffix          = string
    pass_role_arns          = list(string) # task + execution roles of the service
  }))
}

variable "deployment_config_name" {
  description = "How traffic is shifted from blue to green."
  type        = string
  default     = "CodeDeployDefault.ECSCanary10Percent5Minutes"

  validation {
    condition     = startswith(var.deployment_config_name, "CodeDeployDefault.ECS")
    error_message = "Use one of the predefined CodeDeployDefault.ECS* deployment configurations."
  }
}

variable "termination_wait_minutes" {
  description = "Minutes the old (blue) task set keeps running after traffic moved, for instant rollback."
  type        = number
  default     = 5
}

variable "rollback_5xx_threshold" {
  description = "Target 5XX responses per minute that trigger an automatic rollback."
  type        = number
  default     = 5
}
