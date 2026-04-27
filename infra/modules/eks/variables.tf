variable "project_name" {
  description = "Short project identifier."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.35"
}

variable "subnet_ids" {
  description = "Private subnet IDs for the cluster control plane and node group."
  type        = list(string)
}

variable "cluster_role_arn" {
  description = "IAM role ARN for the EKS control plane."
  type        = string
}

variable "node_role_arn" {
  description = "IAM role ARN attached to managed node group instances."
  type        = string
}

variable "ebs_csi_role_arn" {
  description = "Pod Identity role ARN for the EBS CSI controller."
  type        = string
}

variable "aws_lb_controller_role_arn" {
  description = "Pod Identity role ARN for AWS Load Balancer Controller."
  type        = string
}

variable "external_secrets_role_arn" {
  description = "Pod Identity role ARN for External Secrets Operator."
  type        = string
}

variable "argocd_ecr_role_arn" {
  description = "Pod Identity role ARN for ArgoCD repo-server ECR access."
  type        = string
}

variable "admin_principal_arn" {
  description = "IAM principal granted cluster-admin via access entry. Must be set for the operator to kubectl into the cluster."
  type        = string
}

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired node count."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum node count."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum node count."
  type        = number
  default     = 3
}

variable "cluster_log_retention_days" {
  description = "Retention for the cluster's CloudWatch log group."
  type        = number
  default     = 30
}

variable "vpc_cni_addon_version" {
  description = "Pinned EKS add-on version for vpc-cni."
  type        = string
  default     = "v1.21.1-eksbuild.7"
}

variable "kube_proxy_addon_version" {
  description = "Pinned EKS add-on version for kube-proxy."
  type        = string
  default     = "v1.35.3-eksbuild.5"
}

variable "coredns_addon_version" {
  description = "Pinned EKS add-on version for coredns."
  type        = string
  default     = "v1.14.2-eksbuild.4"
}

variable "ebs_csi_addon_version" {
  description = "Pinned EKS add-on version for aws-ebs-csi-driver."
  type        = string
  default     = "v1.59.0-eksbuild.1"
}

variable "pod_identity_agent_addon_version" {
  description = "Pinned EKS add-on version for eks-pod-identity-agent."
  type        = string
  default     = "v1.3.10-eksbuild.3"
}
