output "frontend_url" {
  description = "Public URL of the frontend (HTTPS, self-signed certificate; needs the /etc/hosts entry)."
  value       = "https://${var.domain_name}"
}

output "alb_dns_name" {
  description = "DNS name of the public ALB (resolve it for /etc/hosts: scripts/update-hosts.sh)."
  value       = module.alb.alb_dns_name
}

output "backend_internal_url" {
  description = "Internal ALB in front of the backend (reachable only from frontend tasks)."
  value       = local.backend_url
}

output "tls_certificate_arn" {
  description = "Imported self-signed certificate in ACM."
  value       = module.tls_certificate.acm_certificate_arn
}

output "tls_secret_arn" {
  description = "Secrets Manager secret with the certificate and private key (KMS-encrypted)."
  value       = module.tls_certificate.secret_arn
}

output "tls_certificate_pem" {
  description = "Public certificate (PEM), e.g. to trust it locally."
  value       = module.tls_certificate.certificate_pem
}

output "image_tag_parameters" {
  description = "SSM parameters that trigger a blue/green deployment when changed."
  value       = { for k, p in aws_ssm_parameter.image_tag : k => p.name }
}

output "codedeploy_application" {
  description = "CodeDeploy application and deployment groups."
  value = {
    application = module.codedeploy.app_name
    groups      = module.codedeploy.deployment_group_names
  }
}

output "deployer_function_name" {
  description = "Lambda that turns an SSM image-tag change into a CodeDeploy deployment."
  value       = module.deploy_automation.function_name
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
