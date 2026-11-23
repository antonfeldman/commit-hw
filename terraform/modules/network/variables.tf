variable "name" {
  description = "Name prefix for all network resources."
  type        = string
}

variable "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR."
  }
}

variable "availability_zones" {
  description = "Availability zones to spread subnets across (one subnet of each tier per AZ)."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least two availability zones are required (ALB and RDS subnet group need 2)."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDRs of the public subnets (ALB), one per AZ, same order as availability_zones."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.availability_zones)
    error_message = "public_subnet_cidrs must have one entry per availability zone."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDRs of the private subnets (ECS tasks), one per AZ, same order as availability_zones."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == length(var.availability_zones)
    error_message = "private_subnet_cidrs must have one entry per availability zone."
  }
}

variable "data_subnet_cidrs" {
  description = "CIDRs of the isolated data subnets (RDS), one per AZ, same order as availability_zones."
  type        = list(string)

  validation {
    condition     = length(var.data_subnet_cidrs) == length(var.availability_zones)
    error_message = "data_subnet_cidrs must have one entry per availability zone."
  }
}

variable "db_port" {
  description = "Database port allowed into the data subnets by the network ACL."
  type        = number
  default     = 5432
}

variable "log_retention_days" {
  description = "Retention of the VPC flow log group."
  type        = number
  default     = 30
}
