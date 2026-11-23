variable "name" {
  description = "Name prefix for the ALB resources (max 20 chars to fit ALB/TG name limits)."
  type        = string

  validation {
    condition     = length(var.name) <= 20
    error_message = "name must be 20 characters or fewer (ALB and target group names are limited to 32)."
  }
}

variable "internal" {
  description = "Create an internal ALB (private subnets, not reachable from the internet)."
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC of the target groups."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the ALB (at least two AZs): public subnets for an internet-facing ALB, private for an internal one."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group attached to the ALB."
  type        = string
}

variable "target_name" {
  description = "Short name of the service behind the ALB (used in target group names, e.g. frontend)."
  type        = string

  validation {
    condition     = length(var.target_name) <= 10
    error_message = "target_name must be 10 characters or fewer (target group names are limited to 32)."
  }
}

variable "target_port" {
  description = "Container port of the targets."
  type        = number
}

variable "health_check_path" {
  description = "HTTP path of the target health check."
  type        = string
  default     = "/health"
}

variable "enable_https" {
  description = "Create an HTTPS :443 listener (it becomes the production listener)."
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ACM certificate for the HTTPS listener (required when enable_https = true)."
  type        = string
  default     = null
}

variable "ssl_policy" {
  description = "TLS negotiation policy of the HTTPS listener."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
}

variable "redirect_http_to_https" {
  description = "With HTTPS enabled, answer HTTP :80 with a 301 redirect to HTTPS."
  type        = bool
  default     = true
}

variable "http_port" {
  description = "Port of the HTTP forward listener (used when enable_https = false)."
  type        = number
  default     = 80
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
