# ---- General -----------------------------------------------------------------
variable "project_name" {
  description = "Project name, used as a prefix for resource names."
  type        = string
  default     = "commit-hw"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region. The assignment requires us-east-1."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "This environment must be deployed to us-east-1."
  }
}

variable "log_retention_days" {
  description = "Retention for all CloudWatch log groups."
  type        = number
  default     = 30
}

# ---- Network -----------------------------------------------------------------
variable "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones (one public, private and data subnet in each)."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "Public subnets (ALB)."
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnets (ECS tasks, VPC endpoints)."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "data_subnet_cidrs" {
  description = "Isolated data subnets (RDS). No route to the internet."
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "alb_ingress_cidrs" {
  description = "CIDRs allowed to reach the ALB on HTTP/80."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ---- Application -------------------------------------------------------------
variable "image_tag" {
  description = "Tag of the frontend/backend images in ECR (the git commit SHA pushed by CI or scripts/build-and-push.sh)."
  type        = string

  validation {
    condition     = var.image_tag != "latest" && length(var.image_tag) > 0
    error_message = "Use an immutable tag such as the git commit SHA, not 'latest'."
  }
}

variable "frontend_port" {
  description = "Container port of the frontend."
  type        = number
  default     = 8080
}

variable "backend_port" {
  description = "Container port of the backend."
  type        = number
  default     = 8080
}

variable "app_desired_count" {
  description = "Tasks per application service (2 = one per AZ)."
  type        = number
  default     = 2
}

variable "refresh_seconds" {
  description = "How often (seconds) the frontend page re-pulls the value from the backend."
  type        = number
  default     = 5
}

variable "service_discovery_namespace" {
  description = "Private DNS namespace for service discovery."
  type        = string
  default     = "commit.local"
}

# ---- Database ----------------------------------------------------------------
variable "db_port" {
  description = "PostgreSQL port."
  type        = number
  default     = 5432
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

# ---- Observability -----------------------------------------------------------
variable "otel_collector_version" {
  description = "AWS Distro for OpenTelemetry collector image tag."
  type        = string
  default     = "v0.51.0"
}

variable "otel_collector_desired_count" {
  description = "Number of collector tasks."
  type        = number
  default     = 1
}

variable "otlp_grpc_port" {
  description = "OTLP/gRPC port of the collector."
  type        = number
  default     = 4317
}

variable "metrics_namespace" {
  description = "CloudWatch metrics namespace for OpenTelemetry metrics."
  type        = string
  default     = "CommitHW"
}

# ---- Identity ----------------------------------------------------------------
variable "github_repository" {
  description = "GitHub repository (owner/name) allowed to assume the CI role via OIDC."
  type        = string
}

variable "github_allowed_refs" {
  description = "Git refs allowed to assume the CI role."
  type        = list(string)
  default     = ["refs/heads/main"]
}

variable "create_github_oidc_provider" {
  description = "Create the GitHub OIDC provider (false if the account already has one)."
  type        = bool
  default     = true
}

variable "reviewer_user_name" {
  description = "Name of the read-only IAM user for the reviewer."
  type        = string
  default     = "commit-reviewer"
}
