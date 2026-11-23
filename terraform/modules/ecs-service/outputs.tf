output "service_name" {
  description = "Name of the ECS service."
  value       = aws_ecs_service.this.name
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
