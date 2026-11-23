output "acm_certificate_arn" {
  description = "ARN of the imported ACM certificate (attach to the ALB HTTPS listener)."
  value       = aws_acm_certificate.this.arn
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret holding the certificate and private key."
  value       = aws_secretsmanager_secret.this.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS key that encrypts the secret."
  value       = aws_kms_key.this.arn
}

output "certificate_pem" {
  description = "Public certificate (PEM) - safe to share; useful to trust it locally."
  value       = tls_self_signed_cert.this.cert_pem
}

output "not_after" {
  description = "Certificate expiry (RFC 3339)."
  value       = tls_self_signed_cert.this.validity_end_time
}
