variable "name" {
  description = "Name prefix for the security groups."
  type        = string
}

variable "aws_region" {
  description = "AWS region (used to look up the S3 managed prefix list)."
  type        = string
}

variable "vpc_id" {
  description = "VPC in which to create the security groups."
  type        = string
}

variable "alb_ingress_cidrs" {
  description = "IPv4 CIDRs allowed to reach the ALB on port 80. Defaults to the whole internet (public service)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "frontend_port" {
  description = "Container port of the frontend service."
  type        = number
}

variable "backend_port" {
  description = "Container port of the backend service."
  type        = number
}

variable "db_port" {
  description = "Database port."
  type        = number
  default     = 5432
}

variable "otlp_grpc_port" {
  description = "OTLP/gRPC port exposed by the collector."
  type        = number
  default     = 4317
}
