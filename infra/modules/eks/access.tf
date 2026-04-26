# Access entry for the operator's IAM principal, plus cluster-admin policy
# binding. With bootstrap_cluster_creator_admin_permissions = false this is
# the *only* way to reach the cluster, so the variable is required.
#
# aws_iam_session_context normalizes the input: if the user passes an STS
# session ARN (`arn:aws:sts::...:assumed-role/<role>/<session>`) — what
# `aws sts get-caller-identity` returns under an assumed role — it returns
# the underlying role ARN, which is what EKS access entries require. If the
# user passes a plain IAM user/role ARN it's returned unchanged.
data "aws_iam_session_context" "admin" {
  arn = var.admin_principal_arn
}

resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = data.aws_iam_session_context.admin.issuer_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = data.aws_iam_session_context.admin.issuer_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}
