# Private EKS Portfolio Project

A fully private, GitOps-driven EKS cluster hosting a React/Node/Postgres todo app, with Grafana and ArgoCD on sibling subdomains. Every component runs in private subnets. The Kubernetes API is unreachable from the public internet. Nodes reach AWS exclusively through VPC endpoints — no NAT gateway for cluster traffic. CI runs on a self-hosted GitHub Actions runner inside the VPC. Deployment is GitOps — ArgoCD pulls Helm charts from ECR OCI.

**Purpose:** portfolio / interview demo. Infrastructure is created and destroyed per session.

---

## Architecture

```
                        Internet
                           │
                    ┌──────▼──────┐
                    │  Route 53   │  *.<domain>
                    └──────┬──────┘
                           │ alias A-records
                    ┌──────▼──────────────────┐
                    │  ALB (internet-facing)   │  ACM wildcard TLS
                    │  public subnets          │  single IngressGroup
                    └──┬──────┬──────┬────────┘
                       │      │      │
                    argocd  grafana  todo
                           │
              ┌────────────▼─────────────────────────────────────┐
              │                  VPC 10.0.0.0/16                  │
              │                                                   │
              │  ┌──────────────┐   ┌───────────────────────────┐ │
              │  │ runner subnet │   │   private subnet          │ │
              │  │ 10.0.10/24   │   │   10.0.20/24 (AZ-a)       │ │
              │  │ 10.0.11/24   │   │   10.0.21/24 (AZ-b)       │ │
              │  │              │   │                           │ │
              │  │  GH runner   │   │  EKS managed nodes        │ │
              │  │  bastion     │   │  (t3.medium × 2)          │ │
              │  └──────┬───────┘   └────────────┬──────────────┘ │
              │         │ NAT GW                 │ VPC endpoints  │
              │  ┌──────▼───────┐   ┌────────────▼──────────────┐ │
              │  │ public subnet │   │   DB subnet               │ │
              │  │ 10.0.0/24    │   │   10.0.30/24 (AZ-a)       │ │
              │  │ NAT EIP + GW │   │   RDS Postgres 16          │ │
              │  └──────────────┘   └───────────────────────────┘ │
              └───────────────────────────────────────────────────┘
```

**Key constraints:**
- Cluster API endpoint is private only (`endpoint_public_access = false`)
- EKS nodes have no default route — all AWS API traffic goes through VPC endpoints
- One NAT Gateway, used only by the runner/bastion subnets (not cluster nodes)
- Pod Identity exclusively — no OIDC provider, no IRSA annotations
- All secrets via SSM Parameter Store → External Secrets Operator → Kubernetes Secrets

---

## Prerequisites

| Tool | Version |
|---|---|
| AWS CLI | ≥ 2.x, credentials configured |
| Terraform | ≥ 1.9.0 |
| Docker (with buildx) | Desktop or Engine |
| Helm | ≥ 3.14 |
| kubectl | any recent |
| Session Manager plugin | for SSM bastion access |

A GitHub PAT with `repo` scope on this repository is required before the runner can register.

---

## Configuration

All environment-specific values live in `infra/terraform.tfvars`. Before first apply, copy the example and fill in your values:

```bash
cp infra/terraform.tfvars.example infra/terraform.tfvars
```

Key inputs:

| Variable | Description |
|---|---|
| `project_name` | Short identifier used in all resource names and SSM paths |
| `environment` | e.g. `dev`, `portfolio` |
| `domain_name` | Root domain (must have a Route 53 hosted zone in your account) |
| `hosted_zone_id` | Route 53 hosted zone ID for `domain_name` |
| `github_owner` | GitHub user or org that owns this repo |
| `github_repo` | Repository name (no owner prefix) |
| `admin_principal_arn` | IAM principal ARN granted cluster-admin access |

---

## Repository Layout

```
.
├── .github/workflows/
│   ├── build-backend.yml       # push apps/backend/** → ECR todo-backend:<sha>
│   ├── build-frontend.yml      # push apps/frontend/** → ECR todo-frontend:<sha>
│   └── package-charts.yml      # after builds → bump version, helm push todo + platform charts
├── apps/
│   ├── backend/                # Node/Express API + Dockerfile
│   ├── frontend/               # React/Vite SPA + Dockerfile + nginx
│   └── charts/
│       ├── todo/               # Helm chart for the app (Deployments, Services, Ingress, ExternalSecret)
│       └── platform/           # App-of-apps chart (LBC, ESO, kube-prometheus-stack, ingress, todo)
├── infra/
│   ├── bootstrap/              # S3 + DynamoDB for Terraform state — run once
│   ├── modules/
│   │   ├── network/            # VPC, subnets, NAT, route tables, VPC endpoints
│   │   ├── ecr/                # ECR repositories (app images, mirrored images, OCI charts)
│   │   ├── iam-roles/          # Cluster role, node role, Pod Identity roles
│   │   ├── eks/                # Cluster, managed add-ons, node group, access entries, Pod Identity associations
│   │   ├── rds/                # Postgres 16, SSM connection params, KMS
│   │   ├── bastion/            # Jump host (SSM-only, no public IP)
│   │   ├── runner/             # Self-hosted GitHub Actions runner (ephemeral, self-re-registering)
│   │   ├── dns/                # ACM wildcard cert + Route 53 alias records (two-phase)
│   │   └── secrets/            # SSM KMS key, Grafana admin password
│   └── main.tf                 # Root module wiring all modules together
├── k8s/
│   └── argocd-bootstrap/
│       ├── namespace.yaml      # argocd + external-secrets namespaces
│       ├── argocd-values.yaml  # ArgoCD Helm values — uses <ACCOUNT_ID> placeholder
│       ├── argocd-install.sh   # Bootstrap script — resolves account ID, runs from bastion
│       ├── ecr-creds-sync.yaml # CronJob: refresh ECR token every 6 h
│       └── root-app.yaml       # Seed Application → platform chart in ECR OCI
└── scripts/
    ├── mirror-images.sh        # Pull upstream images → push to ECR
    ├── mirror-charts.sh        # helm pull upstream charts → helm push to ECR OCI
    ├── bootstrap-app-images.sh # Build and push todo app images from local Docker
    └── connect-bastion.sh      # aws ssm start-session wrapper
```

---

## Bootstrap Runbook

### Step 1 — Configure AWS credentials

```bash
aws sts get-caller-identity   # confirm you are authenticated to the right account
```

### Step 2 — Fill in terraform.tfvars

```bash
cp infra/terraform.tfvars.example infra/terraform.tfvars
# edit infra/terraform.tfvars with your domain, hosted_zone_id, github_owner, etc.
```

### Step 3 — Initialize Terraform backend

The bootstrap module creates the S3 bucket and DynamoDB table used as the Terraform backend:

```bash
cd infra/bootstrap
terraform init && terraform apply
```

Copy the `backend_block` output into `infra/backend.tf`, then initialize the root module:

```bash
cd ../
terraform init -migrate-state
```

If a shared backend already exists, skip the bootstrap step and just run `terraform init`.

### Step 4 — Apply infrastructure (phase 1)

```bash
cd infra
terraform fmt -recursive && terraform validate
terraform plan -out phase1.tfplan
terraform apply phase1.tfplan
```

Creates: VPC + endpoints, ECR repos, IAM roles, EKS cluster + node group + add-ons, RDS, bastion, runner, ACM wildcard cert. DNS A-records are skipped until the ALB exists (phase 2).

The runner will fail to register until the GitHub PAT is stored in SSM (next step).

### Step 5 — Store the GitHub PAT

Terraform outputs the exact `aws ssm put-parameter` command with the correct KMS key alias and parameter path. Run it with your real token:

```bash
terraform output -raw runner_pat_put_command
# prints: aws ssm put-parameter --name /... --type SecureString --value ghp_xxx ...
# replace ghp_xxx with your actual PAT and run the command
```

The runner systemd unit retries registration automatically and should come online within ~30 seconds.

### Step 6 — Mirror third-party artifacts to ECR

From the repo root (Docker must be running):

```bash
./scripts/mirror-images.sh    # container images: ArgoCD, LBC, ESO, Prometheus, Grafana, …
./scripts/mirror-charts.sh    # Helm charts: argo-cd, aws-load-balancer-controller, …
```

Both scripts are idempotent — safe to re-run if interrupted.

### Step 7 — Build and push the initial app images

CI handles this on every push, but you need at least one image in ECR before the first ArgoCD sync:

```bash
IMAGE_TAG="$(git rev-parse --short HEAD)" ./scripts/bootstrap-app-images.sh
```

### Step 8 — Fill in chart values and push charts

Edit `apps/charts/platform/values.yaml` and `apps/charts/todo/values.yaml` — replace the `<PLACEHOLDER>` values with outputs from your Terraform apply:

```bash
# Useful outputs
terraform -chdir=infra output -raw ecr_registry_url          # → ecrRegistry
terraform -chdir=infra output -raw cluster_name              # → clusterName
terraform -chdir=infra output -raw wildcard_certificate_arn  # → certificateArn
terraform -chdir=infra output -raw rds_ssm_parameter_prefix  # → ssmPrefix
```

Then push both charts:

```bash
REGISTRY=$(terraform -chdir=infra output -raw ecr_registry_url)

aws ecr get-login-password --region us-east-1 \
  | helm registry login --username AWS --password-stdin "$REGISTRY"

helm package apps/charts/todo     -d /tmp/charts
helm package apps/charts/platform -d /tmp/charts

helm push /tmp/charts/todo-0.1.0.tgz     "oci://${REGISTRY}/charts"
helm push /tmp/charts/platform-0.1.0.tgz "oci://${REGISTRY}/charts"
```

### Step 9 — Connect to the bastion

```bash
./scripts/connect-bastion.sh
```

Inside the bastion, verify cluster access:

```bash
aws eks update-kubeconfig \
  --name "$(aws eks list-clusters --query 'clusters[0]' --output text)" \
  --region us-east-1
kubectl get nodes
# Expected: two nodes in Ready state
```

### Step 10 — Bootstrap ArgoCD (from bastion)

Upload the bootstrap files via the Terraform state bucket (already exists):

```bash
BUCKET=$(terraform -chdir=infra output -raw tfstate_bucket 2>/dev/null \
  || aws s3api list-buckets --query 'Buckets[?contains(Name,`tfstate`)].Name' --output text | head -1)

aws s3 cp k8s/argocd-bootstrap/ "s3://${BUCKET}/bootstrap/" --recursive
```

On the bastion:

```bash
BUCKET=<your-tfstate-bucket-name>
mkdir -p /tmp/argocd
aws s3 cp "s3://${BUCKET}/bootstrap/" /tmp/argocd/ --recursive
chmod +x /tmp/argocd/argocd-install.sh
/tmp/argocd/argocd-install.sh
```

The script:
1. Resolves the AWS account ID and substitutes it into all template files
2. Applies `namespace.yaml` (creates `argocd` and `external-secrets` namespaces)
3. Seeds the `argocd-ecr-creds` Secret with a fresh ECR token
4. Runs `helm upgrade --install argocd oci://…/charts/mirror/argo-cd --version 8.1.2`
5. Waits for the ArgoCD CRDs, then applies `ecr-creds-sync.yaml` and `root-app.yaml`

ArgoCD then syncs the platform chart, deploying: AWS Load Balancer Controller, External Secrets Operator, kube-prometheus-stack (Prometheus + Grafana), ingress rules, and the todo app.

Watch sync progress from the bastion:

```bash
kubectl get applications -n argocd
kubectl get pods -n kube-system   # wait for aws-load-balancer-controller
```

Initial sync takes 3–5 minutes.

### Step 11 — Apply DNS (phase 2)

Once LBC is running it provisions the shared ALB. Collect its DNS name and canonical zone ID:

```bash
aws elbv2 describe-load-balancers \
  --region us-east-1 \
  --query 'LoadBalancers[?Scheme==`internet-facing`].[DNSName,CanonicalHostedZoneId]' \
  --output text
```

Add both values to `infra/terraform.tfvars`:

```hcl
alb_dns_name = "k8s-..."
alb_zone_id  = "Z35SXDOTRQ7X7K"
```

Apply:

```bash
cd infra
terraform plan -out phase2.tfplan
terraform apply phase2.tfplan
```

This creates Route 53 alias A-records for `todo.`, `grafana.`, and `argocd.<your-domain>`.

---

## Verification

After phase 2, all of the following should pass:

```bash
DOMAIN=<your-domain>

# App endpoints return 200 with valid TLS
curl -sI "https://todo.${DOMAIN}"    | head -2
curl -sI "https://grafana.${DOMAIN}" | head -2
curl -sI "https://argocd.${DOMAIN}"  | head -2

# Kubernetes API is unreachable from outside the VPC
ENDPOINT=$(terraform -chdir=infra output -raw cluster_endpoint)
curl --connect-timeout 5 "${ENDPOINT}/version" && echo "FAIL: endpoint is public" || echo "OK: endpoint is private"

# Exactly one NAT Gateway (runner-only)
aws ec2 describe-nat-gateways --region us-east-1 \
  --query 'NatGateways[?State==`available`].NatGatewayId'

# No OIDC providers (Pod Identity-only, per spec)
aws iam list-open-id-connect-providers

# All ArgoCD Applications are Synced + Healthy
kubectl get applications -n argocd

# Todo pods are running and ExternalSecret is synced
kubectl get pods -n todo
kubectl get externalsecret -n todo

# Zero Terraform drift
terraform -chdir=infra plan
```

**End-to-end CI/CD test:** push any change to `apps/backend/src/`, watch the runner pick it up in GitHub, see a new ECR image tag appear, and ArgoCD sync within ~3 minutes.

---

## CI/CD Flow

```
git push apps/backend/**
        │
        ▼
build-backend.yml            (self-hosted runner inside VPC)
  resolve account ID → ECR registry
  docker build → docker push
  image tag = github.sha
        │
        ▼ workflow_run trigger
package-charts.yml
  resolve account ID → ECR registry
  yq: stamp image tags in todo/values.yaml
  bump todo Chart.yaml patch version → helm push oci://ECR/charts
  bump platform Chart.yaml patch version → helm push oci://ECR/charts
        │
        ▼  ArgoCD polls ECR every 3 min
ArgoCD detects new platform chart version
  syncs todo Application → new targetRevision
  helm upgrade todo release → rolling pod update
```

No `kubectl` is ever run from outside the VPC. The runner has ECR push permissions only — it never touches the cluster directly.

---

## Platform Components

| Component | Mirrored chart | Version | Namespace |
|---|---|---|---|
| AWS Load Balancer Controller | `charts/mirror/aws-load-balancer-controller` | 1.13.0 | kube-system |
| External Secrets Operator | `charts/mirror/external-secrets` | 0.10.4 | external-secrets |
| kube-prometheus-stack | `charts/mirror/kube-prometheus-stack` | 66.2.1 | monitoring |
| ArgoCD | `charts/mirror/argo-cd` | 8.1.2 | argocd |
| Todo app | `charts/todo` | CI-bumped | todo |

All images are mirrored from upstream registries into ECR before deployment. The cluster has no default route to the internet — every image pull goes through ECR via the `ecr.dkr` VPC endpoint.

---

## Secrets

| Secret | SSM path | Consumer |
|---|---|---|
| RDS master password | `/<project>/rds/master-password` (SecureString) | ESO → K8s Secret → backend |
| RDS connection params | `/<project>/rds/{host,port,database,username}` | ESO → K8s Secret → backend |
| Grafana admin password | `/<project>/grafana/admin-password` (SecureString) | ESO → K8s Secret → Grafana |
| GitHub PAT | `/<project>/github/pat` (SecureString) | Runner user-data at boot |
| ECR auth token | K8s Secret `argocd-ecr-creds` (refreshed by CronJob every 6 h) | ArgoCD repo-server |

No secret is stored in git or in any Terraform variable.

---

## Teardown

```bash
# 1. Empty ECR repositories (required because repos use IMMUTABLE tags;
#    terraform destroy will fail on non-empty repos)
REGION=us-east-1
for repo in $(aws ecr describe-repositories --region $REGION \
  --query 'repositories[].repositoryName' --output text); do
  IMAGE_IDS=$(aws ecr list-images --region $REGION --repository-name "$repo" \
    --query 'imageIds[*]' --output json)
  [ "$IMAGE_IDS" = "[]" ] && continue
  aws ecr batch-delete-image --region $REGION \
    --repository-name "$repo" --image-ids "$IMAGE_IDS" > /dev/null
done

# 2. Destroy all infrastructure
terraform -chdir=infra destroy

# 3. Check for orphan resources in the AWS console:
#    CloudWatch log groups (/aws/eks/...), EBS volumes, Elastic IPs
```

---

## Cost Estimate (while running)

| Resource | ~Monthly |
|---|---|
| EKS cluster control plane | $72 |
| 2× t3.medium nodes | $60 |
| 11× VPC interface endpoints (2 AZs) | $146 |
| 1× NAT Gateway | $32 |
| RDS db.t4g.micro | $14 |
| ALB | $18 |
| **Total** | **~$342** |

Destroy between demo sessions to avoid idle cost.
