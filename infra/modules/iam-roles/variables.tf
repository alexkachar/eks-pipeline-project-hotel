variable "project_name" {
  description = "Short project identifier used in role names."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "ssm_secrets_kms_key_arn" {
  description = "KMS CMK ARN used to encrypt SSM SecureStrings read by External Secrets Operator."
  type        = string
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs readable by ArgoCD repo-server for OCI Helm charts and mirrored images."
  type        = list(string)
}
