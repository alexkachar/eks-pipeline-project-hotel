#!/usr/bin/env bash
# Start an SSM session into the bastion EC2 instance.
#
# Looks up the instance by Name tag. Override the tag value or region with
# env vars if your project_name/environment differ from the defaults below.

set -euo pipefail

NAME_TAG="${BASTION_NAME:-project-hotel-dev-bastion}"
REGION="${AWS_REGION:-us-east-1}"

INSTANCE_ID=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters \
    "Name=tag:Name,Values=$NAME_TAG" \
    "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" ]]; then
  echo "No running bastion found with Name=$NAME_TAG in $REGION." >&2
  exit 1
fi

echo "Connecting to $INSTANCE_ID ($NAME_TAG, $REGION)..." >&2
exec aws ssm start-session --target "$INSTANCE_ID" --region "$REGION"
