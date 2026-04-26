# network

Four-tier, two-AZ VPC. Public (IGW), runner (NAT), private (no default route), db (no default route).

## Key decisions

- `enable_dns_support` + `enable_dns_hostnames` both `true` — required for interface endpoint private DNS.
- One NAT Gateway in public AZ-a; only runner route tables route through it. Cluster subnets do not.
- S3 gateway endpoint is associated with the **private** route table — missing this silently breaks ECR layer pulls.
- Interface endpoints in both private subnets with `private_dns_enabled = true`.
- **Includes `eks-auth`** (11 interface endpoints, not the 10 listed in CLAUDE.md §2). Required for EKS Pod Identity in a fully-private VPC: the Pod Identity Agent calls `eks-auth.<region>.amazonaws.com` to exchange the projected SA token for AWS credentials. Without it every Pod Identity workload (EBS CSI, ESO, ArgoCD repo-server, AWS LB Controller) will fail credential refresh — the agent daemonset still starts, so failures look like generic "no credentials" errors rather than DNS/network issues. Spec deviation, flagged on purpose.
- Subnet tags: `kubernetes.io/cluster/<name>=shared` on public + private; `role/elb=1` on public; `role/internal-elb=1` on private.

## Inputs

| Name | Default |
|---|---|
| `project_name` | — |
| `environment` | — |
| `cluster_name` | — |
| `vpc_cidr` | `10.0.0.0/16` |
| `azs` | `["us-east-1a", "us-east-1b"]` |

## Outputs

`vpc_id`, `vpc_cidr`, `public_subnet_ids`, `runner_subnet_ids`, `private_subnet_ids`, `db_subnet_ids`, `endpoints_security_group_id`.
