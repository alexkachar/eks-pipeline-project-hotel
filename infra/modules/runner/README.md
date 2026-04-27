# runner

Single self-hosted GitHub Actions runner for this project's monorepo. Lives in the runner subnet (the only one with NAT egress, so it can reach `github.com`, `ghcr.io`, and public image base layers), executes any workflow with `runs-on: [self-hosted, linux, x64, vpc]`.

## Posture

- Private, no public IP, IMDSv2 required, encrypted gp3 root.
- IAM:
  - `ecr:GetAuthorizationToken` on `*` (the API only accepts that)
  - Layer upload + manifest perms scoped to `ecr_repository_arns`
  - `ssm:GetParameter` / `ssm:GetParameters` scoped to the PAT parameter ARN only
  - `kms:Decrypt` scoped to the PAT CMK only
  - `AmazonSSMManagedInstanceCore` for SSM debugging access
- Security group: zero ingress, HTTPS-only egress.

## How registration works (and why there's no two-phase apply)

The PAT lives in SSM Parameter Store at `pat_ssm_parameter_name`, encrypted with the CMK created by this module (`alias/<project>-github-pat`). The PAT itself is created out of band — Terraform never sees the plaintext value.

The runner is **self-healing**: a systemd unit's `ExecStartPre` calls `/usr/local/bin/runner-register.sh` on every start. That script reads the PAT, exchanges it for a short-lived registration token, runs `config.sh --replace`, then `ExecStart` runs `run.sh`. Because the runner is registered as `--ephemeral`, it exits after one job and systemd loops (`Restart=always`, `RestartSec=10`).

A failure in `ExecStartPre` (e.g. PAT not yet in SSM) is treated by systemd as a transient failure and re-attempted automatically. So the apply order is **not** PAT-then-runner; either order works:

- Apply runner first, then `aws ssm put-parameter ...`: runner sits in restart loop until PAT shows up, then comes online within ~10s.
- Seed PAT first, then apply runner: runner registers on first boot.

CLAUDE.md §10 step 3 anticipates a phased apply for this; the self-healing approach makes that phase unnecessary.

## Seeding the PAT

After the first apply (or any time after the KMS alias exists):

```bash
aws ssm put-parameter \
  --name /<project>/github/pat \
  --type SecureString \
  --value "ghp_xxxxxxxxxxxxxxxxxxxx" \
  --key-id alias/<project>-github-pat \
  --overwrite
```

The token must have at minimum `Administration: Read and write` on the target repo (needed to create runner registration tokens). For a fine-grained PAT, scope to the single repo.

To rotate the PAT later, re-run the same `put-parameter` command with `--overwrite`. The next runner restart picks it up — no infra change needed.

## Templating note

User-data and the registration script are **two separate `templatefile()` calls**, not one nested heredoc. The register script is rendered first, base64-encoded, and embedded in user-data via `echo '...' | base64 -d > ...`. This sidesteps the escape problem CLAUDE.md §6.8 flags ("verify it survives shell quoting when templated through Terraform's `templatefile()`") — neither file contains `$$` or quoted heredocs.

## Inputs

| Name | Default |
|---|---|
| `project_name` | — |
| `environment` | — |
| `vpc_id` | — |
| `vpc_cidr` | — |
| `runner_subnet_id` | — single subnet (AZ-a). Must have NAT egress |
| `github_owner` | — e.g. `alexkachar` |
| `github_repo` | — e.g. `eks-pipeline-project-hotel` |
| `pat_ssm_parameter_name` | — e.g. `/<project>/github/pat` |
| `ecr_repository_arns` | — list of ARNs the runner can push to |
| `runner_version` | `2.319.1` |
| `instance_type` | `t3.small` |
| `root_volume_size_gb` | `20` |

## Outputs

`instance_id`, `runner_role_arn`, `kms_key_arn`, `kms_alias`, `security_group_id`, `ssm_session_command`.

## Debugging

```bash
aws ssm start-session --target <instance_id>
sudo systemctl status actions-runner
sudo journalctl -u actions-runner -f
```

If `ExecStartPre` is failing, the journal output usually says either "AccessDenied on SSM GetParameter" (PAT not seeded yet) or "401 Unauthorized" from the GitHub API (PAT lacks `Administration: Read and write`).
