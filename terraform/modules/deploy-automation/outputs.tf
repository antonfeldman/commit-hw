output "function_name" {
  description = "Name of the deployer Lambda."
  value       = aws_lambda_function.deployer.function_name
}

output "log_group_name" {
  description = "Log group of the deployer Lambda."
  value       = aws_cloudwatch_log_group.deployer.name
}

output "event_rule_name" {
  description = "EventBridge rule that reacts to image-tag parameter changes."
  value       = aws_cloudwatch_event_rule.image_tag_changed.name
}
