# iam-roles

Shared IAM roles. Scope limited to what the EKS module needs to stand a cluster up.

- `cluster-role` — trusted by `eks.amazonaws.com`, attached `AmazonEKSClusterPolicy`.
- `node-role` — trusted by `ec2.amazonaws.com`, attached worker, CNI, ECR read-only, SSM managed policies.
- `ebs-csi-role` — trusted by `pods.eks.amazonaws.com` (Pod Identity), attached `AmazonEBSCSIDriverPolicy`.

Pod Identity roles for the AWS LB Controller, External Secrets, and ArgoCD are intentionally omitted here — they are added when the corresponding workloads are in scope.

## Outputs

`cluster_role_arn`, `node_role_arn`, `ebs_csi_role_arn`.
