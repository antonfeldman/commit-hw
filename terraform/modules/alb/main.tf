# -----------------------------------------------------------------------------
# Application Load Balancer with a blue/green target-group pair for CodeDeploy.
# Used twice:
#   * public  (internet-facing): HTTPS :443 -> frontend, HTTP :80 -> 301 to HTTPS
#   * internal (private subnets): HTTP :80 -> backend (traffic never leaves the VPC)
#
# CodeDeploy owns the "production" listener's default action during blue/green
# deployments (it swaps / weights blue and green), so Terraform ignores changes
# to it after creation.
# -----------------------------------------------------------------------------

locals {
  lb_name = var.internal ? "${var.name}-int-alb" : "${var.name}-alb"

  # Blue keeps the original (pre blue/green) name so the existing target group is
  # adopted in place instead of being replaced.
  target_group_names = {
    blue  = "${var.name}-${var.target_name}"
    green = "${var.name}-${var.target_name}-green"
  }

  http_redirect = var.enable_https && var.redirect_http_to_https

  production_listener_arn = var.enable_https ? aws_lb_listener.https[0].arn : aws_lb_listener.http_forward[0].arn
}

resource "aws_lb" "this" {
  name                       = local.lb_name
  load_balancer_type         = "application"
  internal                   = var.internal
  subnets                    = var.subnet_ids
  security_groups            = [var.security_group_id]
  drop_invalid_header_fields = true # mitigates HTTP desync / header smuggling
  enable_deletion_protection = var.enable_deletion_protection
  idle_timeout               = 30

  access_logs {
    bucket  = aws_s3_bucket.access_logs.id
    prefix  = "alb"
    enabled = true
  }

  depends_on = [aws_s3_bucket_policy.access_logs]
}

resource "aws_lb_target_group" "this" {
  for_each = local.target_group_names

  name                 = each.value
  vpc_id               = var.vpc_id
  target_type          = "ip" # required for Fargate (awsvpc)
  port                 = var.target_port
  protocol             = "HTTP"
  deregistration_delay = 15

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = each.value, Color = each.key }
}

# ---- HTTPS :443 (production listener when TLS is enabled) -------------------
resource "aws_lb_listener" "https" {
  count = var.enable_https ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy # TLS 1.3 + TLS 1.2 with forward-secret ciphers only
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this["blue"].arn
  }

  lifecycle {
    ignore_changes = [default_action] # managed by CodeDeploy
  }
}

# ---- HTTP :80 -> 301 redirect to HTTPS --------------------------------------
resource "aws_lb_listener" "http_redirect" {
  count = local.http_redirect ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      protocol    = "HTTPS"
      port        = "443"
      status_code = "HTTP_301"
    }
  }
}

# ---- HTTP forward (production listener when TLS is disabled, e.g. internal) --
resource "aws_lb_listener" "http_forward" {
  count = var.enable_https ? 0 : 1

  load_balancer_arn = aws_lb.this.arn
  port              = var.http_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this["blue"].arn
  }

  lifecycle {
    ignore_changes = [default_action] # managed by CodeDeploy
  }
}

# -----------------------------------------------------------------------------
# Access-log bucket (private, encrypted with SSE-S3 - the only option ALB supports)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "access_logs" {
  bucket_prefix = "${local.lb_name}-logs-"
  force_destroy = var.force_destroy_logs
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket                  = aws_s3_bucket.access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.access_log_retention_days
    }
  }
}

data "aws_elb_service_account" "this" {}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "access_logs" {
  statement {
    sid       = "AllowAlbLogDelivery"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.access_logs.arn}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.this.arn]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.access_logs.arn, "${aws_s3_bucket.access_logs.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  policy = data.aws_iam_policy_document.access_logs.json

  depends_on = [aws_s3_bucket_public_access_block.access_logs]
}
