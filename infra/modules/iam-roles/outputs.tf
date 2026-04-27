output "cluster_role_arn" {
  description = "IAM role assumed by the EKS control plane."
  value       = aws_iam_role.cluster.arn
}

output "node_role_arn" {
  description = "IAM role attached to managed node group EC2 instances."
  value       = aws_iam_role.node.arn
}

output "ebs_csi_role_arn" {
  description = "Pod Identity role for the EBS CSI controller."
  value       = aws_iam_role.ebs_csi.arn
}

output "aws_lb_controller_role_arn" {
  description = "Pod Identity role for AWS Load Balancer Controller."
  value       = aws_iam_role.aws_lb_controller.arn
}

output "external_secrets_role_arn" {
  description = "Pod Identity role for External Secrets Operator."
  value       = aws_iam_role.external_secrets.arn
}

output "argocd_ecr_role_arn" {
  description = "Pod Identity role for ArgoCD repo-server ECR access."
  value       = aws_iam_role.argocd_ecr.arn
}

output "pod_identity_role_arns" {
  description = "Map of platform Pod Identity role ARNs."
  value = {
    ebs_csi           = aws_iam_role.ebs_csi.arn
    aws_lb_controller = aws_iam_role.aws_lb_controller.arn
    external_secrets  = aws_iam_role.external_secrets.arn
    argocd_ecr        = aws_iam_role.argocd_ecr.arn
  }
}
