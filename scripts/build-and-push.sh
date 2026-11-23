#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Build the frontend/backend images for linux/arm64 (Fargate Graviton) and push
# them to ECR, tagged with the current git commit SHA. Also warms the ECR
# pull-through cache with the ADOT collector image.
#
# Uses your local AWS CLI credentials (`aws configure`). In CI the same thing is
# done by .github/workflows/deploy.yml using OIDC.
#
# Usage:  ./scripts/build-and-push.sh [tag]      (default tag: git short SHA)
# -----------------------------------------------------------------------------
set -euo pipefail

REGION="us-east-1"
PROJECT="commit-hw"
OTEL_VERSION="${OTEL_VERSION:-v0.51.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:-$(git -C "${ROOT}" rev-parse --short HEAD)}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "Registry: ${REGISTRY}"
echo "Tag     : ${TAG}"

aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}"

for app in frontend backend; do
  image="${REGISTRY}/${PROJECT}/${app}:${TAG}"
  echo "==> ${image}"
  docker buildx build --platform linux/arm64 --provenance=false \
    -t "${image}" --push "${ROOT}/apps/${app}"
done

# First pull through the cache creates the cached repository in ECR.
echo "==> Warming pull-through cache for ADOT collector ${OTEL_VERSION}"
docker pull --platform linux/arm64 \
  "${REGISTRY}/ecr-public/aws-observability/aws-otel-collector:${OTEL_VERSION}" >/dev/null

echo
echo "Done. Deploy (CodeDeploy blue/green via the SSM trigger) with:"
echo "  aws ssm put-parameter --overwrite --type String --name /${PROJECT}/dev/frontend/image-tag --value ${TAG}"
echo "  aws ssm put-parameter --overwrite --type String --name /${PROJECT}/dev/backend/image-tag  --value ${TAG}"
