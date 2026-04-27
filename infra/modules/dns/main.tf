# Wildcard ACM certificate. DNS-validated through the same Route 53 hosted
# zone the workloads will resolve from.
resource "aws_acm_certificate" "wildcard" {
  domain_name       = "*.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.domain_name}-wildcard"
  }
}

# Validation CNAME(s) — one per name on the cert. With no SANs there's
# exactly one, but the for_each handles the general case.
resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.wildcard.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = var.hosted_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# Block until ACM observes the validation CNAMEs and flips the cert to
# ISSUED. Without this resource, downstream code can pick up an unvalidated
# cert ARN and the ALB listener will refuse it.
resource "aws_acm_certificate_validation" "wildcard" {
  certificate_arn         = aws_acm_certificate.wildcard.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}

# Phase-2 alias records. Skipped on the first apply (alb_dns_name = null);
# populated once the AWS Load Balancer Controller has provisioned the ALB
# and you've fed its DNS name + canonical zone ID back into tfvars.
resource "aws_route53_record" "alias" {
  for_each = var.alb_dns_name == null ? toset([]) : toset(var.subdomains)

  zone_id = var.hosted_zone_id
  name    = "${each.key}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = false
  }
}
