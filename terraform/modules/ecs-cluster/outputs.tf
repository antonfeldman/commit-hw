output "cluster_arn" {
  description = "ARN of the ECS cluster."
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.this.name
}

output "namespace_id" {
  description = "ID of the Cloud Map private DNS namespace."
  value       = aws_service_discovery_private_dns_namespace.this.id
}

output "namespace_name" {
  description = "Name of the Cloud Map private DNS namespace."
  value       = aws_service_discovery_private_dns_namespace.this.name
}
