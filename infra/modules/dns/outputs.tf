output "certificate_arn" {
  description = "ARN of the validated wildcard ACM certificate. Only resolves once validation has completed — safe to feed directly into ALB Ingress annotations."
  value       = aws_acm_certificate_validation.wildcard.certificate_arn
}

output "subdomain_fqdns" {
  description = "Map of subdomain label → fully qualified hostname covered by the wildcard cert."
  value = {
    for s in var.subdomains : s => "${s}.${var.domain_name}"
  }
}

output "alias_records_created" {
  description = "Whether phase-2 A-records have been created. False until alb_dns_name is supplied."
  value       = var.alb_dns_name != null
}
