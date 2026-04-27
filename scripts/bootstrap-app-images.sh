#!/usr/bin/env bash
# Builds and pushes the todo app images to this project's ECR repositories.
#
# Usage:
#   IMAGE_TAG="$(git rev-parse --short HEAD)" ./scripts/bootstrap-app-images.sh
#
# If IMAGE_TAG is not set, the script uses `dev`.

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
IMAGE_TAG="${IMAGE_TAG:-dev}"

login_ecr() {
  aws ecr get-login-password --region "$REGION" \
    | docker login --username AWS --password-stdin "$REGISTRY"
}

image_exists_in_ecr() {
  local repo="$1" tag="$2"
  aws ecr describe-images \
    --region "$REGION" \
    --repository-name "$repo" \
    --image-ids imageTag="$tag" \
    >/dev/null 2>&1
}

build_and_push() {
  local name="$1"
  local context="$2"
  local image="${REGISTRY}/${name}:${IMAGE_TAG}"

  if image_exists_in_ecr "$name" "$IMAGE_TAG"; then
    printf '[skip]  %s already exists in ECR\n' "$image"
    return 0
  fi

  printf '[build] %s from %s\n' "$image" "$context"
  docker build -t "$image" "$context"

  printf '[push]  %s\n' "$image"
  docker push "$image"
}

login_ecr
build_and_push "todo-backend" "apps/backend"
build_and_push "todo-frontend" "apps/frontend"

printf 'Done. Pushed todo app images with tag %s.\n' "$IMAGE_TAG"
