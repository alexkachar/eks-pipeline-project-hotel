#!/bin/bash
# Re-registers the GitHub Actions runner. Invoked by systemd ExecStartPre on
# every start, so the runner is self-healing if the PAT is added or rotated
# after first boot. Failure here just causes systemd to retry — by design.

set -eu

cd /opt/actions-runner

PAT=$(aws ssm get-parameter \
  --name "${pat_ssm_parameter_name}" \
  --with-decryption \
  --query Parameter.Value \
  --output text)

REG_TOKEN=$(curl -sS -X POST \
  -H "Authorization: token $PAT" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${github_owner}/${github_repo}/actions/runners/registration-token" \
  | jq -r .token)

# Best-effort cleanup of any prior registration on this host. `|| true`
# because on a fresh runner directory there's nothing to remove and
# config.sh exits nonzero in that case.
./config.sh remove --token "$REG_TOKEN" 2>/dev/null || true

./config.sh \
  --url "https://github.com/${github_owner}/${github_repo}" \
  --token "$REG_TOKEN" \
  --name "vpc-runner-$(hostname)-$(date +%s)" \
  --labels "self-hosted,linux,x64,vpc" \
  --unattended \
  --ephemeral \
  --replace
