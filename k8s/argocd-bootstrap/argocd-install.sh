#!/usr/bin/env bash
# Bootstrap ArgoCD from the mirrored ECR OCI chart.
#
# Run this from the bastion after `aws eks update-kubeconfig` succeeds.
# Idempotent: helm upgrade --install is safe to re-run.
#
# Prerequisites (already handled by bastion user-data or run manually):
#   aws eks update-kubeconfig --name project-hotel-dev-cluster --region us-east-1
#
# Copy this file to the bastion with:
#   aws ssm send-command \
#     --instance-ids <bastion-id> \
#     --document-name AWS-RunShellScript \
#     --parameters 'commands=["cat > /tmp/argocd-install.sh << '"'"'SCRIPT'"'"'", ...]'
#
# Or use the simpler approach documented in the README: scp via ssm-proxy, then
# run the script directly.

set -euo pipefail

REGION="us-east-1"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
CHART_VERSION="8.1.2"

# ---------------------------------------------------------------------------
# Step 1: create namespaces
# ---------------------------------------------------------------------------
echo "[1/5] Creating namespaces..."
kubectl apply -f /tmp/namespace.yaml

# ---------------------------------------------------------------------------
# Step 2: wait for CRDs to be ready (after first install) or skip (first run)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Step 3: log in to ECR for Helm OCI
# ---------------------------------------------------------------------------
echo "[2/5] Logging in to ECR..."
aws ecr get-login-password --region "${REGION}" \
  | helm registry login --username AWS --password-stdin "${REGISTRY}"

# ---------------------------------------------------------------------------
# Step 4: seed the ECR credentials Secret before ArgoCD starts so repo-server
# can pull the platform chart on its very first sync attempt. The CronJob
# (applied in the next step) will keep it fresh every 6 hours.
# ---------------------------------------------------------------------------
echo "[3/5] Seeding argocd-ecr-creds Secret..."
ECR_TOKEN="$(aws ecr get-login-password --region "${REGION}")"

kubectl create secret generic argocd-ecr-creds \
  --namespace argocd \
  --from-literal=username=AWS \
  --from-literal=password="${ECR_TOKEN}" \
  --dry-run=client -o yaml \
  | kubectl apply -f -

# ---------------------------------------------------------------------------
# Step 5: install / upgrade ArgoCD
# ---------------------------------------------------------------------------
echo "[4/5] Installing ArgoCD ${CHART_VERSION}..."
helm upgrade --install argocd \
  "oci://${REGISTRY}/charts/mirror/argo-cd" \
  --version "${CHART_VERSION}" \
  --namespace argocd \
  --values /tmp/argocd-values.yaml \
  --wait \
  --timeout 10m

# ---------------------------------------------------------------------------
# Step 6: apply the ECR creds refresh CronJob and the root Application
# ---------------------------------------------------------------------------
echo "[5/5] Applying ECR creds CronJob and root Application..."

# Wait for ArgoCD CRDs before applying the Application resource.
kubectl wait --for=condition=Established \
  --timeout=120s \
  crd/applications.argoproj.io

kubectl apply -f /tmp/ecr-creds-sync.yaml
kubectl apply -f /tmp/root-app.yaml

echo ""
echo "ArgoCD is up. Access the UI via:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:80"
echo "  (or via https://argocd.alexanderkachar.com once the ALB is provisioned)"
echo ""
echo "Initial admin password:"
echo "  kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
