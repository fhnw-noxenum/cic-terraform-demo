#!/usr/bin/env bash
# app/build-and-push.sh
#
# Build the image and push it to YOUR ECR repo. Run from the app/ directory
# after your dev stack has been applied (so the ECR repo exists).
#
# Usage:  ./build-and-push.sh v1

set -euo pipefail

TAG="${1:-}"
if [[ -z "$TAG" ]]; then
    echo "Usage: $0 <tag>   e.g. $0 v1"
    exit 1
fi

# Ask Terraform for the repo URL instead of hard-coding it — it contains your
# student name and the account ID.
REPO_URL="$(terraform -chdir=../envs/dev output -raw ecr_repository_url)"
ECR_HOST="${REPO_URL%%/*}"
REGION="$(echo "$ECR_HOST" | cut -d. -f4)"
IMAGE="${REPO_URL}:${TAG}"

echo "==> Building ${IMAGE}"
# Fargate runs x86_64 by default. Without --platform, an Apple-silicon Mac
# builds an arm64 image and the task dies with "exec format error".
docker build --platform linux/amd64 -t "${IMAGE}" .

echo "==> Logging in to ECR"
aws ecr get-login-password --region "${REGION}" \
    | docker login --username AWS --password-stdin "${ECR_HOST}"

echo "==> Pushing ${IMAGE}"
docker push "${IMAGE}"

echo ""
echo "Pushed: ${IMAGE}"
echo ""
echo "Now set in envs/dev/terraform.tfvars:"
echo "  image_uri = \"${IMAGE}\""
echo ""
echo "Then: cd ../envs/dev && terraform apply"
