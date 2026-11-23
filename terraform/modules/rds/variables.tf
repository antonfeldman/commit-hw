variable "name" {
  description = "Name prefix for the database resources."
  type        = string
}

variable "data_subnet_ids" {
  description = "Isolated data subnets for the DB subnet group (at least two AZs)."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group attached to the RDS instance."
  type        = string
}

variable "engine_major_version" {
  description = "PostgreSQL major version (RDS picks the default minor)."
  type        = string
  default     = "17"
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "database_name" {
  description = "Name of the initial database."
  type        = string
  default     = "commit"
}

variable "master_username" {
  description = "Master username (the password is generated and managed by RDS in Secrets Manager)."
  type        = string
  default     = "commitadmin"
}

variable "port" {
  description = "Database port."
  type        = number
  default     = 5432
}

variable "allocated_storage_gb" {
  description = "Initial storage in GiB."
  type        = number
  default     = 20
}

variable "max_allocated_storage_gb" {
  description = "Storage autoscaling ceiling in GiB."
  type        = number
  default     = 50
}

variable "multi_az" {
  description = "Deploy a standby in a second AZ. Off for a cost-conscious test environment."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Automated backup retention in days."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Protect the DB from deletion. Keep false so the test environment can be torn down."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy."
  type        = bool
  default     = true
}
