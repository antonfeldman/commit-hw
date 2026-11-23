variable "name" {
  description = "Service and container name (e.g. frontend)."
  type        = string
}

variable "aws_region" {
  description = "AWS region (for the awslogs driver)."
  type        = string
}

variable "cluster_arn" {
  description = "ARN of the ECS cluster."
  type        = string
}

variable "cluster_name" {
  description = "Name of the ECS cluster (used in role, family and log group names)."
  type        = string
}

variable "image" {
  description = "Full container image URI including tag."
  type        = string
}

variable "ecr_repository_arns" {
  description = "ECR repositories the execution role may pull from (only this service's image)."
  type        = list(string)
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
}

variable "cpu" {
  description = "Task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Task memory in MiB."
  type        = number
  default     = 512
}

variable "cpu_architecture" {
  description = "Fargate CPU architecture. ARM64 (Graviton) is cheaper; images must be built for it."
  type        = string
  default     = "ARM64"

  validation {
    condition     = contains(["ARM64", "X86_64"], var.cpu_architecture)
    error_message = "cpu_architecture must be ARM64 or X86_64."
  }
}

variable "desired_count" {
  description = "Number of running tasks (spread across the given subnets/AZs)."
  type        = number
  default     = 2
}

variable "subnet_ids" {
  description = "Subnets for the task ENIs (private subnets)."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups for the task ENIs."
  type        = list(string)
}

variable "environment" {
  description = "Plain (non-secret) environment variables."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Environment variables injected from Secrets Manager: name => valueFrom ARN (optionally with :json-key::)."
  type        = map(string)
  default     = {}
}

variable "secret_arns" {
  description = "Secret ARNs the execution role may read (must cover every entry in secrets)."
  type        = list(string)
  default     = []
}

variable "command" {
  description = "Optional container command override."
  type        = list(string)
  default     = null
}

variable "container_user" {
  description = "Optional user (uid[:gid]) to run the container as."
  type        = string
  default     = null
}

variable "readonly_root_filesystem" {
  description = "Mount the container root filesystem read-only."
  type        = bool
  default     = true
}

variable "health_check_command" {
  description = "Optional container health check command (ECS format, e.g. [\"CMD\", ...])."
  type        = list(string)
  default     = null
}

variable "create_task_role_policy" {
  description = "Attach task_role_policy_json to the task role. Explicit flag so count is known at plan time."
  type        = bool
  default     = false
}

variable "task_role_policy_json" {
  description = "IAM policy JSON for the task role (permissions for the application itself)."
  type        = string
  default     = null
}

variable "allow_pull_through_cache_import" {
  description = "Grant the execution role permission to populate an ECR pull-through cache repository on first pull."
  type        = bool
  default     = false
}

variable "attach_load_balancer" {
  description = "Register the service in target_group_arn. Explicit flag so the block is known at plan time."
  type        = bool
  default     = false
}

variable "target_group_arn" {
  description = "ALB target group to register the service in (used when attach_load_balancer = true)."
  type        = string
  default     = null
}

variable "enable_service_discovery" {
  description = "Register the service in Cloud Map (DNS A records)."
  type        = bool
  default     = false
}

variable "service_discovery_namespace_id" {
  description = "Cloud Map namespace ID (required when enable_service_discovery = true)."
  type        = string
  default     = null
}

variable "service_discovery_name" {
  description = "DNS name of the service inside the namespace (e.g. backend)."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Retention of the service log group."
  type        = number
  default     = 30
}

variable "deployment_controller" {
  description = "ECS = rolling update managed by ECS; CODE_DEPLOY = blue/green managed by AWS CodeDeploy (requires a load balancer)."
  type        = string
  default     = "ECS"

  validation {
    condition     = contains(["ECS", "CODE_DEPLOY"], var.deployment_controller)
    error_message = "deployment_controller must be ECS or CODE_DEPLOY."
  }
}
