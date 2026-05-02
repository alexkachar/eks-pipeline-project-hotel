#!/usr/bin/env bash
# Tear down the entire project-hotel stack.
#
# Run from the repository root. Requires AWS CLI and Terraform.
#
# Steps:
#   1. Delete the ALB and its target groups (created by the AWS Load Balancer
#      Controller inside Kubernetes — not managed by Terraform). These hold
#      references to the public subnets and the ACM cert, so they must go first
#      or terraform destroy will fail with DependencyViolation errors.
#   2. Empty all ECR repositories (repos block destroy when non-empty).
#   3. terraform destroy (infra/)
#
# The bootstrap S3 + DynamoDB are intentionally left alive so that rebuild.sh
# can reuse them. Destroy those manually if you want a completely clean account:
#   terraform -chdir=infra/bootstrap destroy

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="${REPO_ROOT}/infra"

echo "========================================================"
echo " project-hotel TEARDOWN"
echo " Region : ${REGION}"
echo " Root   : ${REPO_ROOT}"
echo "========================================================"
echo ""

# Confirm intent.
read -r -p "Type 'destroy' to confirm teardown: " CONFIRM
if [[ "$CONFIRM" != "destroy" ]]; then
  echo "Aborted."
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 1: delete the ALB and target groups created by the LBC
# ---------------------------------------------------------------------------
echo ""
echo "[1/3] Deleting LBC-managed ALB and target groups..."

# Resolve the VPC ID from Terraform state so this works even if the VPC was
# recreated with a different ID on a previous rebuild.
VPC_ID=$(terraform -chdir="${INFRA_DIR}" output -raw vpc_id 2>/dev/null || true)

if [[ -z "$VPC_ID" ]]; then
  echo "  Could not read vpc_id from Terraform state. Skipping ALB cleanup."
  echo "  If terraform destroy fails with DependencyViolation, delete the ALB manually."
else
  # Find all ALBs in this VPC.
  ALB_ARNS=$(aws elbv2 describe-load-balancers \
    --region "$REGION" \
    --query "LoadBalancers[?VpcId=='${VPC_ID}'].LoadBalancerArn" \
    --output text 2>/dev/null || true)

  if [[ -z "$ALB_ARNS" ]]; then
    echo "  No ALBs found in VPC ${VPC_ID}. Skipping."
  else
    for arn in $ALB_ARNS; do
      echo "  [delete ALB] ${arn}"
      aws elbv2 delete-load-balancer --region "$REGION" --load-balancer-arn "$arn"
    done

    # Wait for all ALBs to finish deleting before moving on. ENIs linger until
    # the ALB is fully gone, which is what causes the subnet DependencyViolation.
    echo "  Waiting for ALB(s) to finish deleting..."
    for arn in $ALB_ARNS; do
      while true; do
        STATE=$(aws elbv2 describe-load-balancers \
          --region "$REGION" \
          --load-balancer-arns "$arn" \
          --query 'LoadBalancers[0].State.Code' \
          --output text 2>/dev/null || echo "deleted")
        [[ "$STATE" == "deleted" || "$STATE" == "None" || -z "$STATE" ]] && break
        echo "    state: ${STATE} — waiting 10s..."
        sleep 10
      done
    done
    echo "  ALB(s) deleted."
  fi

  # Delete orphaned target groups in this VPC (LBC creates one per service).
  TG_ARNS=$(aws elbv2 describe-target-groups \
    --region "$REGION" \
    --query "TargetGroups[?VpcId=='${VPC_ID}'].TargetGroupArn" \
    --output text 2>/dev/null || true)

  if [[ -z "$TG_ARNS" ]]; then
    echo "  No target groups found in VPC ${VPC_ID}. Skipping."
  else
    for arn in $TG_ARNS; do
      echo "  [delete TG] ${arn}"
      aws elbv2 delete-target-group --region "$REGION" --target-group-arn "$arn"
    done
  fi

  # Delete LBC-managed security groups (k8s-traffic-* and k8s-<group>-* naming).
  # These are left behind after the ALB is deleted and block VPC deletion.
  LBC_SGS=$(aws ec2 describe-security-groups \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'SecurityGroups[?starts_with(GroupName, `k8s-`) == `true`].GroupId' \
    --output text 2>/dev/null || true)

  if [[ -z "$LBC_SGS" ]]; then
    echo "  No LBC security groups found in VPC ${VPC_ID}. Skipping."
  else
    for sg in $LBC_SGS; do
      echo "  [delete SG] ${sg}"
      aws ec2 delete-security-group --region "$REGION" --group-id "$sg"
    done
  fi
fi

# ---------------------------------------------------------------------------
# Step 2: empty ECR repositories so terraform destroy can delete them
# ---------------------------------------------------------------------------
echo ""
echo "[2/3] Emptying ECR repositories..."

REPOS=$(aws ecr describe-repositories \
  --region "$REGION" \
  --query 'repositories[].repositoryName' \
  --output text 2>/dev/null || true)

if [[ -z "$REPOS" ]]; then
  echo "  No ECR repositories found (or none accessible). Skipping."
else
  for repo in $REPOS; do
    IMAGE_IDS=$(aws ecr list-images \
      --region "$REGION" \
      --repository-name "$repo" \
      --query 'imageIds[*]' \
      --output json)

    if [[ "$IMAGE_IDS" == "[]" ]]; then
      echo "  [empty] ${repo}"
      continue
    fi

    echo "  [delete] ${repo}"
    aws ecr batch-delete-image \
      --region "$REGION" \
      --repository-name "$repo" \
      --image-ids "$IMAGE_IDS" \
      >/dev/null
  done
fi

# ---------------------------------------------------------------------------
# Step 3: terraform destroy
# ---------------------------------------------------------------------------
echo ""
echo "[3/3] Running terraform destroy..."
cd "${INFRA_DIR}"
terraform destroy -auto-approve

echo ""
echo "========================================================"
echo " Teardown complete."
echo ""
echo " The Terraform state backend (S3 + DynamoDB) still exists."
echo " rebuild.sh will reuse it. To also destroy the backend:"
echo "   terraform -chdir=${REPO_ROOT}/infra/bootstrap destroy"
echo "========================================================"
