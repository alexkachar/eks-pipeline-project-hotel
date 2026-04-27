# ecr

Per-image ECR repositories backing both the todo app and the mirrored platform stack (ArgoCD, AWS LBC, ESO, kube-prometheus-stack), plus OCI repositories for Helm charts.

## Per-repo settings

- `image_tag_mutability = "IMMUTABLE"` — tags can never be overwritten, so a Kubernetes Deployment that pinned `image:abc123` always resolves to the same bytes.
- `scan_on_push = true` — Basic scanning runs on every push. Findings show up in the ECR console; nothing in this repo gates on them.
- KMS encryption with the AWS-managed `aws/ecr` key.
- `force_delete = true` so `terraform destroy` succeeds even after images have been pushed (portfolio teardown).

## Lifecycle rules (per repo)

1. **Untagged images expire after `untagged_image_expiry_days` days** (default 7). Catches abandoned layers from failed builds.
2. **Keep only the last `tagged_image_retention_count` tagged images** (default 10). Tag pattern `*` matches every tag.

Rule 1 fires first because the spec for tagged retention only applies once a repo has more than N tagged entries; nothing in rule 1's selection overlaps with rule 2's `tagStatus = tagged`.

## Repositories created (default seed list)

Application:
- `todo-frontend`, `todo-backend`

OCI Helm charts:
- `charts/todo` (this repo's app chart)
- `charts/mirror/argocd`, `charts/mirror/aws-load-balancer-controller`, `charts/mirror/external-secrets`, `charts/mirror/kube-prometheus-stack`

Mirrored third-party images:
- `mirror/argoproj/{argocd,redis,dex}`
- `mirror/kubernetes-sigs/aws-load-balancer-controller`
- `mirror/external-secrets/external-secrets`
- `mirror/prometheus-community/{prometheus,alertmanager,node-exporter}`
- `mirror/kube-state-metrics/kube-state-metrics`
- `mirror/grafana/grafana`
- `mirror/prometheus-operator/prometheus-operator`

Override `repository_names` to add or remove. Sub-component images discovered when actually deploying the upstream charts (per CLAUDE.md §6.3) should be appended to that list rather than created ad hoc.

## Inputs

`project_name`, `environment`, `repository_names` (default seed list), `untagged_image_expiry_days` (default `7`), `tagged_image_retention_count` (default `10`).

## Outputs

`registry_id`, `registry_url`, `repository_urls` (map name → URL), `repository_arns` (map name → ARN).
