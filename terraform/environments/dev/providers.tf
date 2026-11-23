# No credentials in code. The AWS provider uses the standard credential chain:
# the profile written by `aws configure` (~/.aws/credentials, outside the repo),
# or AWS_PROFILE / environment variables set in your terminal session.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = var.github_repository
    }
  }
}
