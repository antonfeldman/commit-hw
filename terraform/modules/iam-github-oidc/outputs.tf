output "role_arn" {
  description = "ARN of the role GitHub Actions assumes (store as the AWS_ROLE_ARN repository variable)."
  value       = aws_iam_role.github_actions.arn
}
