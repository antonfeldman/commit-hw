variable "name" {
  description = "Name prefix for endpoint tags."
  type        = string
}

variable "aws_region" {
  description = "AWS region of the endpoints."
  type        = string
}

variable "vpc_id" {
  description = "VPC to attach the endpoints to."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets that get an ENI for each interface endpoint (the private app subnets)."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group attached to the interface endpoints."
  type        = string
}

variable "gateway_route_table_ids" {
  description = "Route tables that get the S3 gateway endpoint route."
  type        = list(string)
}

variable "interface_services" {
  description = "AWS services reached through interface endpoints (suffix after com.amazonaws.<region>.)."
  type        = list(string)
  default = [
    "ecr.api",        # ECR auth + manifests
    "ecr.dkr",        # Docker registry API
    "logs",           # CloudWatch Logs (awslogs driver + EMF metrics)
    "xray",           # X-Ray trace ingestion
    "secretsmanager", # RDS-managed DB credentials
  ]
}
