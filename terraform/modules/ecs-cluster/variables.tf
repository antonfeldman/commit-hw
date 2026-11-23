variable "name" {
  description = "Name of the ECS cluster."
  type        = string
}

variable "vpc_id" {
  description = "VPC for the Cloud Map private DNS namespace."
  type        = string
}

variable "service_discovery_namespace" {
  description = "Private DNS namespace used for service discovery."
  type        = string
  default     = "commit.local"
}
