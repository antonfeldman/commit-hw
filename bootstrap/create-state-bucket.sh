#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# One-time, manual bootstrap of the S3 bucket that stores Terraform state.
#
# Terraform cannot create the bucket that holds its own state, so this is done
# once, by hand, with the AWS CLI (credentials from `aws configure`).
#
# Hardening applied:
#   - Block Public Access (all four settings)
#   - Object Ownership = BucketOwnerEnforced (ACLs disabled)
#   - Versioning enabled (recover from a bad/corrupted state write)
#   - Default encryption SSE-S3 with bucket key
#   - Bucket policy that denies any non-TLS request
#   - Lifecycle rule: expire old state versions after 90 days
#
# Locking uses Terraform's native S3 lock file (use_lockfile = true, TF >= 1.10),
# so no DynamoDB table is required.
#
# Usage:  ./bootstrap/create-state-bucket.sh [project-name]
# -----------------------------------------------------------------------------
set -euo pipefail

PROJECT="${1:-commit-hw}"
REGION="us-east-1"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="${PROJECT}-tfstate-${ACCOUNT_ID}"
BACKEND_FILE="$(cd "$(dirname "$0")/.." && pwd)/terraform/environments/dev/backend.hcl"

echo "Account : ${ACCOUNT_ID}"
echo "Region  : ${REGION}"
echo "Bucket  : ${BUCKET}"

if aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  echo "Bucket already exists - re-applying hardening settings."
else
  # us-east-1 must NOT pass a LocationConstraint.
  aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}" >/dev/null
  echo "Bucket created."
fi

aws s3api put-public-access-block --bucket "${BUCKET}" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws s3api put-bucket-ownership-controls --bucket "${BUCKET}" \
  --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'

aws s3api put-bucket-versioning --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption --bucket "${BUCKET}" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'

aws s3api put-bucket-policy --bucket "${BUCKET}" --policy "$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": ["arn:aws:s3:::${BUCKET}", "arn:aws:s3:::${BUCKET}/*"],
      "Condition": { "Bool": { "aws:SecureTransport": "false" } }
    }
  ]
}
EOF
)"

aws s3api put-bucket-lifecycle-configuration --bucket "${BUCKET}" \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "expire-old-state-versions",
      "Status": "Enabled",
      "Filter": {},
      "NoncurrentVersionExpiration": { "NoncurrentDays": 90 },
      "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 7 }
    }]
  }'

cat > "${BACKEND_FILE}" <<EOF
bucket = "${BUCKET}"
EOF

echo
echo "Done. Wrote ${BACKEND_FILE}"
echo "Next: cd terraform/environments/dev && terraform init -backend-config=backend.hcl"
