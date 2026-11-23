# Remote state in S3 (bucket created manually by bootstrap/create-state-bucket.sh).
# The bucket name is account-specific, so it is supplied at init time:
#   terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # native S3 locking, no DynamoDB table needed
  }
}
