variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project identifier used in resource names and tags."
  type        = string
  default     = "akeks"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "portfolio"
}

variable "admin_principal_arn" {
  description = "IAM principal ARN granted cluster-admin via access entry (e.g. the ARN of the IAM user or role you run terraform / kubectl as)."
  type        = string
}

variable "cluster_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.32"
}

variable "domain_name" {
  description = "Apex domain. The dns module issues a wildcard ACM cert for *.<domain_name> and creates A-records for the app subdomains."
  type        = string
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID for `domain_name`. The zone is assumed to already exist."
  type        = string
}

variable "alb_dns_name" {
  description = "DNS name of the shared ALB. Leave null on the first apply (cert + validation only); fill in after the AWS Load Balancer Controller has provisioned the ALB so phase-2 A-records get created."
  type        = string
  default     = null
}

variable "alb_zone_id" {
  description = "Canonical hosted zone ID of the ALB (not your Route 53 zone). Required iff alb_dns_name is set."
  type        = string
  default     = null
}
