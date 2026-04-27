# dns

Wildcard ACM certificate for `*.<domain_name>`, DNS-validated through the existing Route 53 hosted zone, plus alias A-records pointing each app subdomain at the shared ALB.

The hosted zone itself is **assumed to already exist** (the registrar is pointing at it). Don't pass an arbitrary domain — pass one whose hosted zone you control in the same AWS account.

## Two-phase apply

Per CLAUDE.md §6.9 / §10, the module is designed for a deliberate two-phase apply because the ALB only exists after ArgoCD syncs the AWS Load Balancer Controller and the platform Ingress.

**Phase 1** — first apply, before any cluster ingress exists:
- `alb_dns_name = null`, `alb_zone_id = null` (the defaults).
- Creates: certificate, validation CNAME(s), `aws_acm_certificate_validation`.
- Blocks until ACM marks the cert ISSUED. The cert ARN is now safe to feed into ALB Ingress annotations.
- Skips the A-records.

**Phase 2** — after the ALB exists:
1. Get the ALB's DNS name and canonical hosted zone ID:
   ```bash
   aws elbv2 describe-load-balancers \
     --query 'LoadBalancers[?Scheme==`internet-facing`].[DNSName,CanonicalHostedZoneId]' \
     --output text
   ```
2. Set `alb_dns_name` and `alb_zone_id` in `terraform.tfvars`.
3. `terraform apply` again. Creates A-records for each entry in `subdomains` pointing at the ALB via Alias.

## Why two phases instead of a `data "aws_lb"` lookup

A `data` block could reference the ALB by tag once it exists, but the lookup would fail on the first apply (no ALB to find). Conditionalizing data sources on the cluster's state is finicky in Terraform and breaks `terraform plan` cleanliness. Explicit nullable inputs are simpler and easier to read.

## Inputs

| Name | Default | Notes |
|---|---|---|
| `domain_name` | — | e.g. `yourdomain.com` |
| `hosted_zone_id` | — | Existing Route 53 zone for `domain_name` |
| `subdomains` | `["todo", "grafana", "argocd"]` | Labels that should A-record to the ALB |
| `alb_dns_name` | `null` | ALB DNS name. Leave null in phase 1 |
| `alb_zone_id` | `null` | ALB's canonical zone (not your R53 zone). Required iff `alb_dns_name` is set |

## Outputs

`certificate_arn` (only resolves once validated), `subdomain_fqdns`, `alias_records_created`.
