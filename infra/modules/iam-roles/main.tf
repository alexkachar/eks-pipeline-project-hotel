locals {
  name_prefix = "${var.project_name}-${var.environment}"

  pod_identity_subjects = {
    ebs_csi = {
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
    }
    aws_lb_controller = {
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
    external_secrets = {
      namespace       = "external-secrets"
      service_account = "external-secrets"
    }
    argocd_ecr = {
      namespace       = "argocd"
      service_account = "argocd-repo-server"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# EKS cluster role.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${local.name_prefix}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
}

resource "aws_iam_role_policy_attachment" "cluster_eks" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------------------------------------------------------------------------
# EKS managed node group role.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${local.name_prefix}-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_ro" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ---------------------------------------------------------------------------
# Pod Identity roles. The trust policy is restricted to the Kubernetes
# namespace + service account that Terraform associates with each role.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "pod_identity_assume" {
  for_each = local.pod_identity_subjects

  statement {
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
    ]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes-namespace"
      values   = [each.value.namespace]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes-service-account"
      values   = [each.value.service_account]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${local.name_prefix}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume["ebs_csi"].json
}

resource "aws_iam_role_policy_attachment" "ebs_csi_managed" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_iam_role" "aws_lb_controller" {
  name               = "${local.name_prefix}-aws-lb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume["aws_lb_controller"].json
}

resource "aws_iam_policy" "aws_lb_controller" {
  name        = "${local.name_prefix}-aws-lb-controller"
  description = "Official AWS Load Balancer Controller IAM policy for v2.13.0."
  policy      = file("${path.module}/aws-load-balancer-controller-iam-policy.json")
}

resource "aws_iam_role_policy_attachment" "aws_lb_controller" {
  role       = aws_iam_role.aws_lb_controller.name
  policy_arn = aws_iam_policy.aws_lb_controller.arn
}

resource "aws_iam_role" "external_secrets" {
  name               = "${local.name_prefix}-external-secrets-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume["external_secrets"].json
}

data "aws_iam_policy_document" "external_secrets" {
  statement {
    sid = "ReadProjectParameters"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = [
      "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/*",
    ]
  }

  statement {
    sid = "DecryptProjectSecureStrings"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = [var.ssm_secrets_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "external_secrets" {
  name   = "external-secrets-ssm-read"
  role   = aws_iam_role.external_secrets.id
  policy = data.aws_iam_policy_document.external_secrets.json
}

resource "aws_iam_role" "argocd_ecr" {
  name               = "${local.name_prefix}-argocd-ecr-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume["argocd_ecr"].json
}

data "aws_iam_policy_document" "argocd_ecr" {
  statement {
    sid       = "ECRGetAuthToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "ECRReadOCIArtifacts"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_role_policy" "argocd_ecr" {
  name   = "argocd-ecr-read"
  role   = aws_iam_role.argocd_ecr.id
  policy = data.aws_iam_policy_document.argocd_ecr.json
}
