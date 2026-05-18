#!/usr/bin/env bash
# app/build-and-push.sh
#
# Build the image and push it to ECR. Run from the app/ directory after
# the dev stack has been applied (so the ECR repo exists).
#
# Usage:  ./build-and-push.sh v1.0

set -euo pipefail

TAG="${1:-}"
if [[ -z "$TAG" ]]; then
    echo "Usage: $0 <tag>   e.g. $0 v1.0"
    exit 1
fi

REGION="${AWS_REGION:-eu-central-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR_HOST="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
REPO="inference-api"
IMAGE="${ECR_HOST}/${REPO}:${TAG}"

echo "==> Building ${IMAGE}"
docker build -t "${IMAGE}" .

echo "==> Logging in to ECR"
aws ecr get-login-password --region "${REGION}" \
    | docker login --username AWS --password-stdin "${ECR_HOST}"

echo "==> Pushing ${IMAGE}"
docker push "${IMAGE}"

echo ""
echo "Pushed: ${IMAGE}"
echo ""
echo "Now update envs/dev/dev.tfvars:"
echo "  image_uri = \"${IMAGE}\""
echo ""
echo "Then: cd ../envs/dev && terraform apply -var-file=dev.tfvars"
