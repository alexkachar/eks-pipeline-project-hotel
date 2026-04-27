variable "domain_name" {
  description = "Apex domain (e.g. alexanderkachar.com). The ACM certificate covers `*.<domain_name>`."
  type        = string
}

variable "hosted_zone_id" {
  description = "Pre-existing Route 53 hosted zone ID for `domain_name`. The hosted zone is assumed to already exist (registrar pointing at it)."
  type        = string
}

variable "subdomains" {
  description = "Subdomain labels that should resolve to the shared ALB. Each becomes <label>.<domain_name>."
  type        = list(string)
  default     = ["todo", "grafana", "argocd"]
}

variable "alb_dns_name" {
  description = "DNS name of the ALB the ingress points to. Leave null on the first apply (cert + validation only); fill in after the AWS Load Balancer Controller has provisioned the ALB."
  type        = string
  default     = null
}

variable "alb_zone_id" {
  description = "Canonical hosted zone ID of the ALB itself (NOT your Route 53 zone — the AWS-published zone that ALBs in this region live in). Required iff alb_dns_name is set."
  type        = string
  default     = null
}
