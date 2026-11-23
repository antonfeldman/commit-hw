output "user_name" {
  description = "Name of the read-only IAM user."
  value       = aws_iam_user.reviewer.name
}

output "user_arn" {
  description = "ARN of the read-only IAM user."
  value       = aws_iam_user.reviewer.arn
}

output "console_sign_in_url" {
  description = "Console sign-in URL for the reviewer."
  value       = "https://${data.aws_caller_identity.current.account_id}.signin.aws.amazon.com/console"
}
