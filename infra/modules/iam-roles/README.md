# iam-roles

Shared IAM roles for the EKS control plane, nodes, and platform workloads that use EKS Pod Identity.

- `cluster-role` — trusted by `eks.amazonaws.com`, attached `AmazonEKSClusterPolicy`.
- `node-role` — trusted by `ec2.amazonaws.com`, attached worker, CNI, ECR read-only, SSM managed policies.
- `ebs-csi-role` — trusted by `pods.eks.amazonaws.com` (Pod Identity), attached `AmazonEBSCSIDriverPolicy`.
- `aws-lb-controller-role` — Pod Identity role for `kube-system/aws-load-balancer-controller`, attached to the official AWS Load Balancer Controller v2.13.0 IAM policy JSON committed beside this module.
- `external-secrets-role` — Pod Identity role for `external-secrets/external-secrets`, allowed to read `/<project>/*` SSM parameters and decrypt the shared SSM secrets CMK.
- `argocd-ecr-role` — Pod Identity role for `argocd/argocd-repo-server`, allowed to fetch ECR auth and read OCI chart/mirror repositories.

Each Pod Identity trust policy is scoped to its expected namespace and service account through EKS session request tags.

## Outputs

`cluster_role_arn`, `node_role_arn`, `ebs_csi_role_arn`, `aws_lb_controller_role_arn`, `external_secrets_role_arn`, `argocd_ecr_role_arn`, `pod_identity_role_arns`.
