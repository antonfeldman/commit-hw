output "repository_urls" {
  description = "Map of short name to repository URL."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "repository_arns" {
  description = "Map of short name to repository ARN."
  value       = { for k, r in aws_ecr_repository.this : k => r.arn }
}

output "pull_through_cache_prefix" {
  description = "Prefix of the ECR Public pull-through cache."
  value       = aws_ecr_pull_through_cache_rule.ecr_public.ecr_repository_prefix
}
