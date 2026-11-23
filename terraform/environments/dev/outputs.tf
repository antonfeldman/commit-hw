output "frontend_url" {
  description = "Public URL of the frontend (HTTP)."
  value       = "http://${module.alb.alb_dns_name}"
}

output "ecr_repository_urls" {
  description = "ECR repositories for the application images."
  value       = module.ecr.repository_urls
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster."
  value       = module.ecs_cluster.cluster_name
}

output "rds_address" {
  description = "Private hostname of the PostgreSQL instance (reachable only from backend tasks)."
  value       = module.rds.address
}

output "db_secret_arn" {
  description = "ARN of the RDS-managed secret with the DB credentials."
  value       = module.rds.master_user_secret_arn
}

output "github_actions_role_arn" {
  description = "Set this as the AWS_ROLE_ARN variable in the GitHub repository settings."
  value       = module.github_oidc.role_arn
}

output "reviewer_user_name" {
  description = "Read-only IAM user for the reviewer."
  value       = module.readonly_reviewer.user_name
}

output "reviewer_console_url" {
  description = "Console sign-in URL for the reviewer."
  value       = module.readonly_reviewer.console_sign_in_url
}

output "xray_trace_map_url" {
  description = "CloudWatch X-Ray trace map (service map) in the AWS console."
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#xray:service-map/map"
}
