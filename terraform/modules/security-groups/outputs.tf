output "alb_sg_id" {
  description = "Security group of the ALB."
  value       = aws_security_group.alb.id
}

output "frontend_sg_id" {
  description = "Security group of the frontend tasks."
  value       = aws_security_group.frontend.id
}

output "backend_sg_id" {
  description = "Security group of the backend tasks."
  value       = aws_security_group.backend.id
}

output "otel_collector_sg_id" {
  description = "Security group of the ADOT collector tasks."
  value       = aws_security_group.otel_collector.id
}

output "rds_sg_id" {
  description = "Security group of the RDS instance."
  value       = aws_security_group.rds.id
}

output "vpc_endpoints_sg_id" {
  description = "Security group of the interface VPC endpoints."
  value       = aws_security_group.vpc_endpoints.id
}

output "backend_alb_sg_id" {
  description = "Security group of the internal (backend) ALB."
  value       = aws_security_group.backend_alb.id
}
