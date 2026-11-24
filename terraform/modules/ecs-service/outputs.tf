output "service_name" {
  description = "Name of the ECS service."
  value       = one(concat(aws_ecs_service.this[*].name, aws_ecs_service.blue_green[*].name))
}

output "task_role_arn" {
  description = "ARN of the task role."
  value       = aws_iam_role.task.arn
}

output "execution_role_arn" {
  description = "ARN of the execution role."
  value       = aws_iam_role.execution.arn
}

output "log_group_name" {
  description = "CloudWatch log group of the service."
  value       = aws_cloudwatch_log_group.this.name
}

output "task_definition_arn" {
  description = "ARN of the current task definition revision."
  value       = aws_ecs_task_definition.this.arn
}

output "task_definition_family" {
  description = "Task definition family (new revisions are registered by the deploy pipeline)."
  value       = aws_ecs_task_definition.this.family
}

output "container_name" {
  description = "Name of the application container."
  value       = var.name
}
