# ---------------------------------------------------------------------------
# Networking addons — installed right after the cluster so the node group can
# bring up kubelet with working pod networking.
# ---------------------------------------------------------------------------
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  addon_version               = var.vpc_cni_addon_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    env = {
      ENABLE_PREFIX_DELEGATION = "true"
    }
  })
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  addon_version               = var.kube_proxy_addon_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# ---------------------------------------------------------------------------
# Pod Identity agent — must exist before any pod_identity_association becomes
# useful. No pod-side dependency though, so it can install right after the
# cluster.
# ---------------------------------------------------------------------------
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "eks-pod-identity-agent"
  addon_version               = var.pod_identity_agent_addon_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# ---------------------------------------------------------------------------
# Post-node-group addons. CoreDNS schedules as a Deployment with no nodes to
# land on until the node group is up, so defer it. Same story for EBS CSI,
# which additionally needs the Pod Identity association.
# ---------------------------------------------------------------------------
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  addon_version               = var.coredns_addon_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    replicaCount = 2
  })

  depends_on = [aws_eks_node_group.default]
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = var.ebs_csi_role_arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}

resource "aws_eks_pod_identity_association" "aws_lb_controller" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = var.aws_lb_controller_role_arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}

resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = var.external_secrets_role_arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}

resource "aws_eks_pod_identity_association" "argocd_ecr" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "argocd"
  service_account = "argocd-repo-server"
  role_arn        = var.argocd_ecr_role_arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = var.ebs_csi_addon_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # The controller's startup health check makes a real EC2 dry-run call,
  # which means it has to wait on the Pod Identity round-trip and a working
  # AWS API path. First-create regularly takes 10–15 minutes; bump the
  # default 20-minute create timeout so a slow first apply doesn't fail.
  timeouts {
    create = "30m"
    update = "30m"
  }

  depends_on = [
    aws_eks_node_group.default,
    aws_eks_addon.coredns,
    aws_eks_pod_identity_association.ebs_csi,
  ]
}
