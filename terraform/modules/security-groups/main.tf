# -----------------------------------------------------------------------------
# Least-privilege security groups. Every rule is explicit and references another
# security group (or the S3 prefix list) - there is no "allow all egress" anywhere.
#
#   Internet --443/80--> ALB --app--> frontend --80--> internal ALB --app--> backend --5432--> RDS
#                                       |                                     |
#                                       +-----------4317--> otel-collector <--+
#   frontend/backend/collector --443--> VPC interface endpoints / S3 gateway
#
# Note: aws_security_group created by Terraform has its default allow-all egress
# rule removed, so a group with no egress rules denies all outbound traffic.
# -----------------------------------------------------------------------------

data "aws_prefix_list" "s3" {
  name = "com.amazonaws.${var.aws_region}.s3"
}

resource "aws_security_group" "alb" {
  name = "${var.name}-alb"
  # Description is immutable (changing it replaces the group), so it keeps its Phase 1 text.
  description = "Public ALB: HTTP from allowed CIDRs, forwards to frontend only"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-alb" }
}

resource "aws_security_group" "backend_alb" {
  name        = "${var.name}-backend-alb"
  description = "Internal ALB: HTTP from frontend tasks only, forwards to backend only"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-backend-alb" }
}

resource "aws_security_group" "frontend" {
  name        = "${var.name}-frontend"
  description = "Frontend ECS tasks"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-frontend" }
}

resource "aws_security_group" "backend" {
  name        = "${var.name}-backend"
  description = "Backend ECS tasks"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-backend" }
}

resource "aws_security_group" "otel_collector" {
  name        = "${var.name}-otel-collector"
  description = "ADOT collector ECS tasks (OTLP in, X-Ray/CloudWatch out via endpoints)"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-otel-collector" }
}

resource "aws_security_group" "rds" {
  name        = "${var.name}-rds"
  description = "RDS PostgreSQL: only reachable from backend tasks"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-rds" }
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.name}-vpc-endpoints"
  description = "Interface VPC endpoints: HTTPS from ECS tasks only"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-vpc-endpoints" }
}

locals {
  # Workloads that need AWS APIs (ECR pull, CloudWatch Logs, Secrets Manager, X-Ray).
  endpoint_clients = {
    frontend       = aws_security_group.frontend.id
    backend        = aws_security_group.backend.id
    otel_collector = aws_security_group.otel_collector.id
  }

  # Workloads that send OTLP to the collector.
  otlp_clients = {
    frontend = aws_security_group.frontend.id
    backend  = aws_security_group.backend.id
  }
}

# ---- ALB ---------------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each = toset(var.alb_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTP from the internet (answered with a 301 redirect to HTTPS)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each = toset(var.alb_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from the internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "alb_to_frontend" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to frontend tasks"
  ip_protocol                  = "tcp"
  from_port                    = var.frontend_port
  to_port                      = var.frontend_port
  referenced_security_group_id = aws_security_group.frontend.id
}

# ---- Frontend ----------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "frontend_from_alb" {
  security_group_id            = aws_security_group.frontend.id
  description                  = "Traffic and health checks from the ALB"
  ip_protocol                  = "tcp"
  from_port                    = var.frontend_port
  to_port                      = var.frontend_port
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "frontend_to_backend_alb" {
  security_group_id            = aws_security_group.frontend.id
  description                  = "Call backend API through the internal ALB"
  ip_protocol                  = "tcp"
  from_port                    = var.backend_alb_port
  to_port                      = var.backend_alb_port
  referenced_security_group_id = aws_security_group.backend_alb.id
}

# ---- Internal ALB (backend) ----------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "backend_alb_from_frontend" {
  security_group_id            = aws_security_group.backend_alb.id
  description                  = "API calls from frontend tasks"
  ip_protocol                  = "tcp"
  from_port                    = var.backend_alb_port
  to_port                      = var.backend_alb_port
  referenced_security_group_id = aws_security_group.frontend.id
}

resource "aws_vpc_security_group_egress_rule" "backend_alb_to_backend" {
  security_group_id            = aws_security_group.backend_alb.id
  description                  = "Forward to backend tasks"
  ip_protocol                  = "tcp"
  from_port                    = var.backend_port
  to_port                      = var.backend_port
  referenced_security_group_id = aws_security_group.backend.id
}

# ---- Backend -----------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "backend_from_backend_alb" {
  security_group_id            = aws_security_group.backend.id
  description                  = "Traffic and health checks from the internal ALB"
  ip_protocol                  = "tcp"
  from_port                    = var.backend_port
  to_port                      = var.backend_port
  referenced_security_group_id = aws_security_group.backend_alb.id
}

resource "aws_vpc_security_group_egress_rule" "backend_to_rds" {
  security_group_id            = aws_security_group.backend.id
  description                  = "PostgreSQL"
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = aws_security_group.rds.id
}

# ---- RDS (no egress rules = no outbound) -------------------------------------
resource "aws_vpc_security_group_ingress_rule" "rds_from_backend" {
  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL from backend tasks only"
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = aws_security_group.backend.id
}

# ---- OTLP: apps -> collector -------------------------------------------------
resource "aws_vpc_security_group_egress_rule" "otlp_to_collector" {
  for_each = local.otlp_clients

  security_group_id            = each.value
  description                  = "OTLP/gRPC to the ADOT collector"
  ip_protocol                  = "tcp"
  from_port                    = var.otlp_grpc_port
  to_port                      = var.otlp_grpc_port
  referenced_security_group_id = aws_security_group.otel_collector.id
}

resource "aws_vpc_security_group_ingress_rule" "collector_from_apps" {
  for_each = local.otlp_clients

  security_group_id            = aws_security_group.otel_collector.id
  description                  = "OTLP/gRPC from ${each.key}"
  ip_protocol                  = "tcp"
  from_port                    = var.otlp_grpc_port
  to_port                      = var.otlp_grpc_port
  referenced_security_group_id = each.value
}

# ---- AWS APIs via VPC endpoints (no internet) --------------------------------
resource "aws_vpc_security_group_egress_rule" "to_interface_endpoints" {
  for_each = local.endpoint_clients

  security_group_id            = each.value
  description                  = "HTTPS to VPC interface endpoints"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.vpc_endpoints.id
}

resource "aws_vpc_security_group_egress_rule" "to_s3_gateway" {
  for_each = local.endpoint_clients

  security_group_id = each.value
  description       = "HTTPS to S3 gateway endpoint (ECR image layers)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = data.aws_prefix_list.s3.id
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_clients" {
  for_each = local.endpoint_clients

  security_group_id            = aws_security_group.vpc_endpoints.id
  description                  = "HTTPS from ${each.key}"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = each.value
}
