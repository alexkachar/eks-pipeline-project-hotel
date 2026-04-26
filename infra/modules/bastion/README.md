# bastion

Single private EC2 instance reachable only via SSM Session Manager. Hosts `kubectl`, `helm`, and the `argocd` CLI for operating the private EKS cluster.

## Posture

- No public IP. No inbound SG rules. SSM-only access.
- IMDSv2 required, encrypted gp3 root EBS.
- IAM role: `AmazonSSMManagedInstanceCore` + an inline policy granting `eks:DescribeCluster` on this cluster's ARN only.
- Cluster admin via an EKS access entry created here (so the entry is torn down with the bastion).

## Subnet placement — spec deviation

CLAUDE.md §6.7 says "private subnet AZ-a", but §2 says private subnets have no default route. The spec's user-data downloads `kubectl`, `helm`, and `argocd` from `dl.k8s.io`, GitHub releases, and `raw.githubusercontent.com` — none of which are reachable from a subnet without internet egress.

This module accepts a `subnet_id` input. The root composition passes the **runner subnet AZ-a** (which routes through the existing single NAT). Every security property §6.7 asks for is preserved (no public IP, SSM-only, no inbound, encrypted EBS, IMDSv2 required) — the only thing that changes is which route table the ENI sits behind. If you ever pre-bake an AMI with the tools, switch the input to a private subnet and the user-data will still work (the AWS API calls to `eks:DescribeCluster` resolve through the in-VPC interface endpoints).

## User-data

Installs awscli/git/tar/gzip via `dnf`, downloads kubectl/helm/argocd, then runs `aws eks update-kubeconfig` for `ec2-user`. The kubeconfig step is wrapped in `|| true` so a race against the cluster's first ACTIVE transition doesn't fail the boot — just re-run it once after first SSM login.

## Inputs

`project_name`, `environment`, `region`, `vpc_id`, `vpc_cidr`, `subnet_id`, `cluster_name`, `cluster_arn`, `instance_type` (default `t3.micro`), `root_volume_size_gb` (default `20`).

## Outputs

`instance_id`, `instance_role_arn`, `security_group_id`, `private_ip`, `ssm_session_command`.
