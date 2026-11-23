output "app_name" {
  description = "CodeDeploy application name."
  value       = aws_codedeploy_app.this.name
}

output "app_arn" {
  description = "CodeDeploy application ARN."
  value       = aws_codedeploy_app.this.arn
}

output "deployment_group_names" {
  description = "Deployment group name per service."
  value       = { for k, g in aws_codedeploy_deployment_group.this : k => g.deployment_group_name }
}

output "deployment_group_arns" {
  description = "Deployment group ARN per service."
  value       = { for k, g in aws_codedeploy_deployment_group.this : k => g.arn }
}

output "deployment_config_arn" {
  description = "ARN of the deployment configuration in use."
  value       = "arn:${local.partition}:codedeploy:${local.region}:${local.account_id}:deploymentconfig:${var.deployment_config_name}"
}
