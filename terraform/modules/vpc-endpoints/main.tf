# -----------------------------------------------------------------------------
# Private access to AWS APIs from subnets that have NO route to the internet.
# -----------------------------------------------------------------------------

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_services)

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [var.security_group_id]
  private_dns_enabled = true

  tags = { Name = "${var.name}-${replace(each.value, ".", "-")}" }
}

# Gateway endpoint for S3 (free). ECR stores image layers in S3.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.gateway_route_table_ids
  policy            = data.aws_iam_policy_document.s3_endpoint.json

  tags = { Name = "${var.name}-s3" }
}

# Least privilege on the endpoint itself: only the ECR layer bucket can be read through it.
data "aws_iam_policy_document" "s3_endpoint" {
  statement {
    sid       = "AllowEcrImageLayersOnly"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::prod-${var.aws_region}-starport-layer-bucket/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}
