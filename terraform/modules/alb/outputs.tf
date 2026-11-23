output "alb_dns_name" {
  description = "DNS name of the ALB."
  value       = aws_lb.this.dns_name
}

output "alb_arn" {
  description = "ARN of the ALB."
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "ARN suffix of the ALB (CloudWatch metric dimension)."
  value       = aws_lb.this.arn_suffix
}

output "blue_target_group_arn" {
  description = "Target group the ECS service registers into at creation."
  value       = aws_lb_target_group.this["blue"].arn
}

output "target_group_names" {
  description = "Blue and green target group names (CodeDeploy target group pair)."
  value       = { for k, tg in aws_lb_target_group.this : k => tg.name }
}

output "production_listener_arn" {
  description = "Listener that CodeDeploy shifts between blue and green (HTTPS if enabled, else HTTP)."
  value       = local.production_listener_arn
}

output "listener_arns" {
  description = "All listener ARNs (the ECS service must wait for them)."
  value = concat(
    aws_lb_listener.https[*].arn,
    aws_lb_listener.http_redirect[*].arn,
    aws_lb_listener.http_forward[*].arn,
  )
}
