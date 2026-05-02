#!/usr/bin/env bash
# Rebuild the entire project-hotel stack from scratch.
#
# Run from the repository root. Requires:
#   - AWS CLI configured (the same identity used to destroy)
#   - Terraform >= 1.9
#   - Docker Desktop running (for mirror-images.sh and bootstrap-app-images.sh)
#   - helm >= 3.14, kubectl, yq (mikefarah/yq v4)
#
# The script is idempotent — re-running after a partial failure resumes from
# the next incomplete step. Each step is guarded so it can be skipped safely.
#
# ============================================================
# PREREQUISITES (must be true before running this script)
# ============================================================
#
# 1. The Terraform state backend (S3 bucket + DynamoDB table) must already
#    exist. If you ran teardown.sh it was preserved. If not, recreate it:
#      terraform -chdir=infra/bootstrap init && terraform -chdir=infra/bootstrap apply
#    Then update infra/backend.tf with the new bucket name.
#
# 2. The GitHub PAT must be re-stored in SSM after Terraform creates the KMS
#    key. The script will print the exact command and pause for you to run it
#    before continuing. Have the PAT ready (GitHub → Settings → Developer
#    settings → Personal access tokens → classic, repo scope).
#
# 3. infra/terraform.tfvars must have alb_dns_name / alb_zone_id CLEARED (or
#    commented out) for phase-1 apply. The script handles this automatically
#    by temporarily removing those lines.

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="${REPO_ROOT}/infra"
SCRIPTS_DIR="${REPO_ROOT}/scripts"

# Values that are constant across rebuilds — must match infra/terraform.tfvars.
PROJECT_NAME="project-hotel"
ENVIRONMENT="dev"
CLUSTER_NAME="${PROJECT_NAME}-${ENVIRONMENT}-cluster"
DOMAIN_NAME="alexanderkachar.com"

# Chart versions to push to ECR OCI.
# root-app.yaml currently targets platform 0.1.5; todo is referenced by
# platform/values.yaml as 0.1.2. Keep these in sync with those files.
# CI bumps patch versions on every push; for a fresh rebuild we push a known
# version so ArgoCD finds the chart it expects.
TODO_CHART_VERSION="0.1.2"
PLATFORM_CHART_VERSION="0.1.5"
ARGOCD_CHART_VERSION="8.1.2"

# Platform chart target revision that root-app.yaml references.
ROOT_APP_PLATFORM_VERSION="0.1.5"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo ""; echo ">>> $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }
pause() {
  echo ""
  echo "-------------------------------------------------------------------"
  echo "  $*"
  echo "  Press ENTER when done."
  echo "-------------------------------------------------------------------"
  read -r _
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' not found in PATH"
}

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
log "Preflight checks..."
require_cmd aws
require_cmd terraform
require_cmd docker
require_cmd helm
require_cmd kubectl
require_cmd yq

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "  Account  : ${ACCOUNT_ID}"
echo "  Registry : ${REGISTRY}"
echo "  Region   : ${REGION}"
echo "  Project  : ${PROJECT_NAME} / ${ENVIRONMENT}"

# Verify Docker is running.
docker info >/dev/null 2>&1 || die "Docker daemon is not running. Start Docker Desktop first."

echo ""
read -r -p "Confirmed — proceed with full rebuild? [y/N] " CONFIRM
[[ "${CONFIRM,,}" == "y" ]] || { echo "Aborted."; exit 0; }

# ---------------------------------------------------------------------------
# Step 1: Terraform phase 1
# Strip alb_dns_name / alb_zone_id so this is a clean phase-1 apply.
# ---------------------------------------------------------------------------
log "[1/9] Terraform phase 1 (all infra except DNS A-records)..."

cd "${INFRA_DIR}"

# Back up tfvars and remove alb lines so phase-1 succeeds even if they are set.
TFVARS="${INFRA_DIR}/terraform.tfvars"
TFVARS_BAK="${INFRA_DIR}/terraform.tfvars.phase1bak"
cp "$TFVARS" "$TFVARS_BAK"

# Remove alb_dns_name and alb_zone_id lines in-place if they are present.
grep -v '^\s*alb_dns_name\s*=' "$TFVARS_BAK" \
  | grep -v '^\s*alb_zone_id\s*=' \
  > "$TFVARS"

terraform init -reconfigure
terraform fmt -recursive
terraform validate
terraform plan -out infra-phase1.tfplan
terraform apply infra-phase1.tfplan

# Restore full tfvars (alb values will be filled in at step 9).
cp "$TFVARS_BAK" "$TFVARS"

# ---------------------------------------------------------------------------
# Step 2: store GitHub PAT
# ---------------------------------------------------------------------------
log "[2/9] Store GitHub PAT in SSM..."

PAT_CMD="$(terraform -chdir="${INFRA_DIR}" output -raw runner_pat_put_command)"
KMS_ALIAS="$(terraform -chdir="${INFRA_DIR}" output -raw runner_kms_alias)"

echo ""
echo "  Run the following command, replacing 'ghp_xxx' with your actual PAT:"
echo ""
echo "  ${PAT_CMD}"
echo ""
pause "Paste and run the command above in another terminal, then press ENTER here."

# Verify the parameter exists before continuing.
aws ssm get-parameter \
  --name "/${PROJECT_NAME}/github/pat" \
  --with-decryption \
  --region "${REGION}" \
  --query 'Parameter.Name' \
  --output text >/dev/null \
  || die "SSM parameter /${PROJECT_NAME}/github/pat not found. Store the PAT first."

echo "  PAT stored successfully."

# ---------------------------------------------------------------------------
# Step 3: mirror third-party images and charts
# ---------------------------------------------------------------------------
log "[3/9] Mirroring third-party images into ECR..."
cd "${REPO_ROOT}"
"${SCRIPTS_DIR}/mirror-images.sh"

log "[3/9] Mirroring third-party Helm charts into ECR..."
"${SCRIPTS_DIR}/mirror-charts.sh"

# ---------------------------------------------------------------------------
# Step 4: build and push initial todo app images
# ---------------------------------------------------------------------------
log "[4/9] Building and pushing todo app images..."
cd "${REPO_ROOT}"
IMAGE_TAG="$(git rev-parse HEAD)"
export IMAGE_TAG
"${SCRIPTS_DIR}/bootstrap-app-images.sh"
echo "  Todo images pushed with tag: ${IMAGE_TAG}"

# ---------------------------------------------------------------------------
# Step 5: update chart values and push charts to ECR OCI
# ---------------------------------------------------------------------------
log "[5/9] Updating chart values and pushing charts to ECR OCI..."

CERT_ARN="$(terraform -chdir="${INFRA_DIR}" output -raw wildcard_certificate_arn)"
RDS_PREFIX="$(terraform -chdir="${INFRA_DIR}" output -raw rds_ssm_parameter_prefix)"
GRAFANA_PARAM="$(terraform -chdir="${INFRA_DIR}" output -raw grafana_admin_password_parameter_name)"
VPC_ID="$(terraform -chdir="${INFRA_DIR}" output -raw vpc_id)"

echo "  CERT_ARN     : ${CERT_ARN}"
echo "  RDS_PREFIX   : ${RDS_PREFIX}"
echo "  GRAFANA_PARAM: ${GRAFANA_PARAM}"
echo "  VPC_ID       : ${VPC_ID}"
echo "  IMAGE_TAG    : ${IMAGE_TAG}"

# Update todo/values.yaml
yq -i "
  .imageRegistry = \"${REGISTRY}\" |
  .domainName = \"${DOMAIN_NAME}\" |
  .frontend.image.tag = \"${IMAGE_TAG}\" |
  .backend.image.tag = \"${IMAGE_TAG}\" |
  .rds.ssmPrefix = \"${RDS_PREFIX}\" |
  .externalSecrets.region = \"${REGION}\" |
  .ingress.host = \"todo.${DOMAIN_NAME}\" |
  .ingress.groupName = \"${PROJECT_NAME}\" |
  .ingress.certificateArn = \"${CERT_ARN}\"
" "${REPO_ROOT}/apps/charts/todo/values.yaml"

# Update platform/values.yaml
yq -i "
  .global.ecrRegistry = \"${REGISTRY}\" |
  .global.region = \"${REGION}\" |
  .global.clusterName = \"${CLUSTER_NAME}\" |
  .global.vpcId = \"${VPC_ID}\" |
  .ingress.groupName = \"${PROJECT_NAME}\" |
  .ingress.certificateArn = \"${CERT_ARN}\" |
  .ingress.argocdHost = \"argocd.${DOMAIN_NAME}\" |
  .ingress.grafanaHost = \"grafana.${DOMAIN_NAME}\" |
  .ingress.todoHost = \"todo.${DOMAIN_NAME}\" |
  .prometheus.grafana.adminPasswordSsmParameter = \"${GRAFANA_PARAM}\" |
  .todo.chartVersion = \"${TODO_CHART_VERSION}\" |
  .todo.ssmPrefix = \"${RDS_PREFIX}\"
" "${REPO_ROOT}/apps/charts/platform/values.yaml"

# Pin the platform targetRevision in root-app.yaml to match.
# (The file uses <ACCOUNT_ID> placeholder — do not substitute here; argocd-install.sh handles that at runtime.)
sed -i "s|targetRevision:.*|targetRevision: ${ROOT_APP_PLATFORM_VERSION}|" \
  "${REPO_ROOT}/k8s/argocd-bootstrap/root-app.yaml"

# Login to ECR for Helm OCI and push charts.
aws ecr get-login-password --region "${REGION}" \
  | helm registry login --username AWS --password-stdin "${REGISTRY}"

rm -rf /tmp/ph-charts && mkdir -p /tmp/ph-charts

helm lint "${REPO_ROOT}/apps/charts/todo"
helm lint "${REPO_ROOT}/apps/charts/platform"

helm package "${REPO_ROOT}/apps/charts/todo" \
  --version "${TODO_CHART_VERSION}" \
  -d /tmp/ph-charts

helm package "${REPO_ROOT}/apps/charts/platform" \
  --version "${PLATFORM_CHART_VERSION}" \
  -d /tmp/ph-charts

helm push "/tmp/ph-charts/todo-${TODO_CHART_VERSION}.tgz" \
  "oci://${REGISTRY}/charts"

helm push "/tmp/ph-charts/platform-${PLATFORM_CHART_VERSION}.tgz" \
  "oci://${REGISTRY}/charts"

echo "  Charts pushed."

# ---------------------------------------------------------------------------
# Step 6: upload bootstrap files to S3 and run ArgoCD install on bastion
# ---------------------------------------------------------------------------
log "[6/9] Uploading bootstrap files to S3 and bootstrapping ArgoCD..."

# Use the Terraform state bucket as the staging bucket.
BOOTSTRAP_BUCKET="alexanderkachar-terraform-state"

aws s3 cp "${REPO_ROOT}/k8s/argocd-bootstrap/" \
  "s3://${BOOTSTRAP_BUCKET}/bootstrap/" \
  --recursive

BASTION_CMD="$(terraform -chdir="${INFRA_DIR}" output -raw bastion_ssm_session_command)"

echo ""
echo "  Bootstrap files uploaded to s3://${BOOTSTRAP_BUCKET}/bootstrap/"
echo ""
echo "  Now connect to the bastion and run the install script."
echo "  Open a NEW terminal and run:"
echo ""
echo "    ${BASTION_CMD}"
echo ""
echo "  Inside the bastion session, run:"
echo ""
echo "    export AWS_REGION=${REGION}"
echo "    export CLUSTER_NAME=${CLUSTER_NAME}"
echo "    export BOOTSTRAP_BUCKET=${BOOTSTRAP_BUCKET}"
echo "    aws eks update-kubeconfig --name \"\$CLUSTER_NAME\" --region \"\$AWS_REGION\""
echo "    kubectl get nodes   # verify nodes are Ready"
echo "    mkdir -p /tmp/argocd"
echo "    aws s3 cp \"s3://\${BOOTSTRAP_BUCKET}/bootstrap/\" /tmp/argocd/ --recursive"
echo "    chmod +x /tmp/argocd/argocd-install.sh"
echo "    /tmp/argocd/argocd-install.sh"
echo ""
pause "Complete the bastion steps above, wait for 'kubectl get applications -n argocd' to show all apps Synced, then press ENTER."

# ---------------------------------------------------------------------------
# Step 7: collect ALB DNS name after LBC provisions it
# ---------------------------------------------------------------------------
log "[7/9] Collecting ALB DNS name..."

echo "  Waiting for internet-facing ALB to appear (up to 10 minutes)..."
ALB_INFO=""
for i in $(seq 1 20); do
  ALB_INFO=$(aws elbv2 describe-load-balancers \
    --region "${REGION}" \
    --query 'LoadBalancers[?Scheme==`internet-facing`].[DNSName,CanonicalHostedZoneId]' \
    --output text 2>/dev/null || true)

  if [[ -n "$ALB_INFO" ]]; then
    break
  fi
  echo "  Attempt ${i}/20 — ALB not found yet, waiting 30s..."
  sleep 30
done

if [[ -z "$ALB_INFO" ]]; then
  echo ""
  echo "  ALB not found automatically. Retrieve it manually:"
  echo ""
  echo "    aws elbv2 describe-load-balancers --region ${REGION} \\"
  echo "      --query 'LoadBalancers[?Scheme==\`internet-facing\`].[DNSName,CanonicalHostedZoneId]' \\"
  echo "      --output text"
  echo ""
  read -r -p "  Paste the ALB DNS name here: " ALB_DNS_NAME
  read -r -p "  Paste the ALB Canonical Hosted Zone ID here: " ALB_ZONE_ID
else
  ALB_DNS_NAME=$(echo "$ALB_INFO" | awk '{print $1}')
  ALB_ZONE_ID=$(echo "$ALB_INFO" | awk '{print $2}')
  echo "  ALB DNS name  : ${ALB_DNS_NAME}"
  echo "  ALB Zone ID   : ${ALB_ZONE_ID}"
fi

# ---------------------------------------------------------------------------
# Step 8: write ALB values into terraform.tfvars and apply phase 2 (DNS)
# ---------------------------------------------------------------------------
log "[8/9] Applying Terraform phase 2 (DNS A-records)..."

# Write alb values into tfvars (replace existing lines or append).
if grep -q '^\s*alb_dns_name\s*=' "$TFVARS"; then
  sed -i "s|^\s*alb_dns_name\s*=.*|alb_dns_name = \"${ALB_DNS_NAME}\"|" "$TFVARS"
else
  echo "alb_dns_name = \"${ALB_DNS_NAME}\"" >> "$TFVARS"
fi

if grep -q '^\s*alb_zone_id\s*=' "$TFVARS"; then
  sed -i "s|^\s*alb_zone_id\s*=.*|alb_zone_id  = \"${ALB_ZONE_ID}\"|" "$TFVARS"
else
  echo "alb_zone_id  = \"${ALB_ZONE_ID}\"" >> "$TFVARS"
fi

   

# ---------------------------------------------------------------------------
# Step 9: verify
# ---------------------------------------------------------------------------
log "[9/9] Verification..."

echo "  Waiting 30s for DNS to propagate..."
sleep 30

echo ""
echo "  EKS endpoint access:"
aws eks describe-cluster \
  --name "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --query 'cluster.resourcesVpcConfig.{public:endpointPublicAccess,private:endpointPrivateAccess}' \
  --output table

echo ""
echo "  HTTPS smoke tests:"
for subdomain in todo grafana argocd; do
  STATUS=$(curl -sk -o /dev/null -w "%{http_code}" \
    "https://${subdomain}.${DOMAIN_NAME}" || echo "FAILED")
  echo "    https://${subdomain}.${DOMAIN_NAME} => ${STATUS}"
done

# Clean up backup.
rm -f "${TFVARS_BAK}"

echo ""
echo "========================================================"
echo " Rebuild complete!"
echo ""
echo " todo    : https://todo.${DOMAIN_NAME}"
echo " grafana : https://grafana.${DOMAIN_NAME}"
echo " argocd  : https://argocd.${DOMAIN_NAME}"
echo ""
echo " ArgoCD initial admin password:"
echo "   (from bastion) kubectl get secret argocd-initial-admin-secret \\"
echo "     -n argocd -o jsonpath='{.data.password}' | base64 -d"
echo "========================================================"
