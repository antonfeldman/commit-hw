output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "IDs of the private (application) subnets."
  value       = [for s in aws_subnet.private : s.id]
}

output "data_subnet_ids" {
  description = "IDs of the isolated data subnets."
  value       = [for s in aws_subnet.data : s.id]
}

output "private_route_table_id" {
  description = "Route table of the private subnets (used for the S3 gateway endpoint)."
  value       = aws_route_table.private.id
}

output "data_route_table_id" {
  description = "Route table of the isolated data subnets."
  value       = aws_route_table.data.id
}
