locals {
  # Stable keys (AZ name) instead of list indexes, so adding/removing an AZ never reshuffles subnets.
  public_subnets  = { for idx, az in var.availability_zones : az => var.public_subnet_cidrs[idx] }
  private_subnets = { for idx, az in var.availability_zones : az => var.private_subnet_cidrs[idx] }
  data_subnets    = { for idx, az in var.availability_zones : az => var.data_subnet_cidrs[idx] }
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true # required for VPC interface endpoints (private DNS) and Cloud Map
  enable_dns_hostnames = true

  tags = { Name = "${var.name}-vpc" }
}

# Lock down the default security group: no ingress, no egress.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-default-sg-unused" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-igw" }
}

# -----------------------------------------------------------------------------
# Subnets
# -----------------------------------------------------------------------------
resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = false # only the ALB lives here; nothing gets a public IP implicitly

  tags = { Name = "${var.name}-public-${each.key}", Tier = "public" }
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = { Name = "${var.name}-private-${each.key}", Tier = "private" }
}

resource "aws_subnet" "data" {
  for_each = local.data_subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = { Name = "${var.name}-data-${each.key}", Tier = "data" }
}

# -----------------------------------------------------------------------------
# Route tables
#   public  : local + 0.0.0.0/0 -> IGW
#   private : local only (+ S3 gateway endpoint route, added by vpc-endpoints module).
#             AWS APIs are reached through VPC interface endpoints - no NAT, no internet.
#   data    : local only. Fully isolated - no route to 0.0.0.0/0, no IGW, no NAT.
# -----------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table" "data" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-data-rt-isolated" }
}

resource "aws_route_table_association" "data" {
  for_each = aws_subnet.data

  subnet_id      = each.value.id
  route_table_id = aws_route_table.data.id
}

# -----------------------------------------------------------------------------
# Network ACL for the data tier (defence in depth on top of security groups).
# Only PostgreSQL from the private (app) subnets in, only ephemeral replies out.
# -----------------------------------------------------------------------------
resource "aws_network_acl" "data" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = [for s in aws_subnet.data : s.id]

  tags = { Name = "${var.name}-data-nacl" }
}

resource "aws_network_acl_rule" "data_ingress_db" {
  for_each = local.private_subnets

  network_acl_id = aws_network_acl.data.id
  rule_number    = 100 + index(var.availability_zones, each.key)
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = each.value
  from_port      = var.db_port
  to_port        = var.db_port
}

resource "aws_network_acl_rule" "data_egress_ephemeral" {
  for_each = local.private_subnets

  network_acl_id = aws_network_acl.data.id
  rule_number    = 100 + index(var.availability_zones, each.key)
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = each.value
  from_port      = 1024
  to_port        = 65535
}

# -----------------------------------------------------------------------------
# VPC Flow Logs -> CloudWatch Logs (audit of all accepted/rejected traffic)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/vpc/${var.name}/flow-logs"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "flow_logs" {
  name               = "${var.name}-vpc-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
}

data "aws_iam_policy_document" "flow_logs" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs.arn}:*"]
  }

  statement {
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"] # Describe* does not support resource-level permissions
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "write-flow-logs"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs.json
}

resource "aws_flow_log" "this" {
  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn             = aws_iam_role.flow_logs.arn
  max_aggregation_interval = 60

  tags = { Name = "${var.name}-flow-log" }
}
