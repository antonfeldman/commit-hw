variable "name" {
  description = "Namespace prefix for the repositories (<name>/<repo>)."
  type        = string
}

variable "repository_names" {
  description = "Repositories to create, e.g. [\"frontend\", \"backend\"]."
  type        = list(string)
}

variable "force_delete" {
  description = "Allow terraform destroy to delete repositories that still contain images."
  type        = bool
  default     = true
}

variable "keep_last_images" {
  description = "Number of images to retain per repository."
  type        = number
  default     = 10
}

variable "pull_through_cache_prefix" {
  description = "Repository prefix for the ECR Public pull-through cache."
  type        = string
  default     = "ecr-public"
}
