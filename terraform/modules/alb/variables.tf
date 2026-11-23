variable "name" {
  description = "Name prefix for the ALB resources (max ~20 chars to fit ALB/TG name limits)."
  type        = string

  validation {
    condition     = length(var.name) <= 20
    error_message = "name must be 20 characters or fewer (ALB and target group names are limited to 32)."
  }
}

variable "vpc_id" {
  description = "VPC of the target group."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for the ALB (at least two AZs)."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group attached to the ALB."
  type        = string
}

variable "frontend_port" {
  description = "Container port of the frontend targets."
  type        = number
}

variable "enable_deletion_protection" {
  description = "Protect the ALB from deletion. Keep false for a disposable test environment."
  type        = bool
  default     = false
}

variable "force_destroy_logs" {
  description = "Allow terraform destroy to delete the access-log bucket even if it contains logs."
  type        = bool
  default     = true
}

variable "access_log_retention_days" {
  description = "Days to keep ALB access logs."
  type        = number
  default     = 30
}
