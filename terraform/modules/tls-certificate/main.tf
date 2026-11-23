# -----------------------------------------------------------------------------
# Self-signed TLS certificate for the public ALB.
#
#   tls_private_key ──► tls_self_signed_cert ──► ACM (imported) ──► ALB :443
#          │                    │
#          └────────┬───────────┘
#                   ▼
#   Secrets Manager (encrypted with a dedicated KMS key) - the system of record
#   for the private key, so it can be re-imported or rotated without Terraform.
#
# Note: Terraform keeps the private key in its state. The state bucket is private,
# encrypted, versioned and TLS-only, and only administrators can read it.
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 2048 # RSA-2048 is the widest-supported key type for ACM imports
}

resource "tls_self_signed_cert" "this" {
  private_key_pem = tls_private_key.this.private_key_pem

  subject {
    common_name  = var.domain_name
    organization = var.organization
  }

  dns_names = distinct(concat([var.domain_name], var.subject_alternative_names))

  validity_period_hours = var.validity_period_hours
  early_renewal_hours   = var.early_renewal_hours

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
  ]
}

# Imported (not ACM-issued) certificate: ACM does not renew it - Terraform does,
# via early_renewal_hours. create_before_destroy lets the ALB swap certificates
# without a window where the listener has none.
resource "aws_acm_certificate" "this" {
  private_key      = tls_private_key.this.private_key_pem
  certificate_body = tls_self_signed_cert.this.cert_pem

  tags = { Name = var.domain_name }

  lifecycle {
    create_before_destroy = true
  }
}

# ---- KMS key dedicated to the TLS secret ------------------------------------
data "aws_iam_policy_document" "kms" {
  # Standard key policy: delegate access control to IAM in this account.
  # Without this statement the key would become unmanageable.
  statement {
    sid       = "EnableIamPolicies"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "this" {
  description             = "Encrypts the TLS private key secret for ${var.domain_name}"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}-tls"
  target_key_id = aws_kms_key.this.key_id
}

# ---- Secrets Manager --------------------------------------------------------
resource "aws_secretsmanager_secret" "this" {
  # name_prefix: a destroyed secret keeps its name reserved during the recovery
  # window; a prefix lets the environment be torn down and recreated at once.
  name_prefix             = "${var.name}/tls/${var.domain_name}-"
  description             = "Self-signed TLS certificate and private key for ${var.domain_name} (imported into ACM)"
  kms_key_id              = aws_kms_key.this.arn
  recovery_window_in_days = var.secret_recovery_window_days
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id = aws_secretsmanager_secret.this.id
  secret_string = jsonencode({
    domain          = var.domain_name
    certificate_pem = tls_self_signed_cert.this.cert_pem
    private_key_pem = tls_private_key.this.private_key_pem
    acm_arn         = aws_acm_certificate.this.arn
  })
}
