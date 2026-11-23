output "alb_dns_name" {
  description = "Public DNS name of the ALB."
  value       = aws_lb.this.dns_name
}

output "alb_arn" {
  description = "ARN of the ALB."
  value       = aws_lb.this.arn
}

output "frontend_target_group_arn" {
  description = "Target group the frontend ECS service registers into."
  value       = aws_lb_target_group.frontend.arn
}

output "listener_arn" {
  description = "ARN of the HTTP listener (ECS service must wait for it)."
  value       = aws_lb_listener.http.arn
}
