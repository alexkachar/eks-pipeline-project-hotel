#!/usr/bin/env bash
# Mirror upstream container images into this project's ECR registry.
#
# Idempotent: skips images whose tag already exists in the destination repo.
# Re-run after editing IMAGES below to add freshly-discovered sub-components.
#
# Versions below are starter values. As you bring up the platform charts,
# `helm template` will reveal the exact image tags each chart pulls — append
# any missing entries here and re-run. ECR repos are tag-immutable so an
# accidental tag overwrite will fail loudly.

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# format: "<source_image_with_tag>=<dest_repo_with_tag>"
# source includes the upstream registry; dest is the ECR repo path + tag.
IMAGES=(
  # ArgoCD
  "quay.io/argoproj/argocd:v3.0.6=mirror/argoproj/argocd:v3.0.6"
  "public.ecr.aws/docker/library/redis:7.4.1-alpine=mirror/argoproj/redis:7.4.1-alpine"
  "ghcr.io/dexidp/dex:v2.41.1=mirror/argoproj/dex:v2.41.1"

  # AWS Load Balancer Controller
  "public.ecr.aws/eks/aws-load-balancer-controller:v2.13.0=mirror/kubernetes-sigs/aws-load-balancer-controller:v2.13.0"

  # External Secrets Operator
  "ghcr.io/external-secrets/external-secrets:v0.10.4=mirror/external-secrets/external-secrets:v0.10.4"

  # kube-prometheus-stack family
  "quay.io/prometheus/prometheus:v2.55.1=mirror/prometheus-community/prometheus:v2.55.1"
  "quay.io/prometheus/alertmanager:v0.27.0=mirror/prometheus-community/alertmanager:v0.27.0"
  "quay.io/prometheus/node-exporter:v1.8.2=mirror/prometheus-community/node-exporter:v1.8.2"
  "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.13.0=mirror/kube-state-metrics/kube-state-metrics:v2.13.0"
  "docker.io/grafana/grafana:11.3.0=mirror/grafana/grafana:11.3.0"
  "quay.io/prometheus-operator/prometheus-operator:v0.78.1=mirror/prometheus-operator/prometheus-operator:v0.78.1"
)

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

mirror_one() {
  local src="$1" dest="$2"
  local repo="${dest%:*}"
  local tag="${dest##*:}"

  if image_exists_in_ecr "$repo" "$tag"; then
    printf '[skip] %s:%s already in ECR\n' "$repo" "$tag"
    return 0
  fi

  printf '[pull] %s\n' "$src"
  docker pull "$src"

  local target="${REGISTRY}/${dest}"
  printf '[tag]  %s -> %s\n' "$src" "$target"
  docker tag "$src" "$target"

  printf '[push] %s\n' "$target"
  docker push "$target"
}

main() {
  login_ecr
  local mirrored=0
  for entry in "${IMAGES[@]}"; do
    src="${entry%%=*}"
    dest="${entry#*=}"
    mirror_one "$src" "$dest"
    ((mirrored++)) || true
  done
  printf 'Done. Processed %d image(s).\n' "$mirrored"
}

main "$@"
