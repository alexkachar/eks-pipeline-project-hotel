# eks

Private EKS cluster with managed node group and the baseline add-on set.

## Posture

- `endpoint_public_access = false`, `endpoint_private_access = true` — API reachable only from within the VPC.
- `authentication_mode = "API"` with `bootstrap_cluster_creator_admin_permissions = false`. No aws-auth ConfigMap, no implicit creator admin. Access comes exclusively from access entries.
- Control-plane logs (`api`, `audit`, `authenticator`) go to a Terraform-managed CloudWatch log group with retention set.
- Secrets are envelope-encrypted with a dedicated KMS CMK created here.

## Addons

Installed in dependency order:

1. `vpc-cni` (with `ENABLE_PREFIX_DELEGATION=true`) and `kube-proxy` before nodes — kubelet needs both to come up healthy.
2. `eks-pod-identity-agent` — prerequisite for Pod Identity associations.
3. Node group.
4. `coredns` — deferred until nodes exist so the Deployment has targets.
5. `aws-ebs-csi-driver` — deferred until nodes + the `ebs-csi-controller-sa` Pod Identity association exist.

Versions use `data.aws_eks_addon_version` with `most_recent = true` at first apply. Promote to explicit pinned strings in `variables.tf` once a known-good version is captured.

## Access

A single access entry grants the principal in `admin_principal_arn` the managed `AmazonEKSClusterAdminPolicy`, scoped to the cluster. Without setting this variable the cluster will provision but nobody can talk to it.

## Inputs

`project_name`, `environment`, `cluster_name`, `cluster_version` (default `1.32`), `subnet_ids`, `cluster_role_arn`, `node_role_arn`, `ebs_csi_role_arn`, `admin_principal_arn`, node sizing vars, `cluster_log_retention_days`.

## Outputs

`cluster_name`, `cluster_arn`, `cluster_endpoint`, `cluster_ca_data`, `cluster_oidc_issuer_url`, `node_security_group_id`, `secrets_kms_key_arn`.
