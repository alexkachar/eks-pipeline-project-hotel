# platform chart

App-of-apps Helm chart. When ArgoCD syncs this chart it creates child Application resources and direct Kubernetes objects that together bring up the full platform stack.

## What it deploys

| Template | Kind | Namespace | Notes |
|---|---|---|---|
| `lbc.yaml` | Application | argocd | AWS Load Balancer Controller — provisions the shared ALB |
| `eso.yaml` | Application | argocd | External Secrets Operator — syncs SSM params to K8s Secrets |
| `prometheus.yaml` | Application + ExternalSecret | argocd / monitoring | kube-prometheus-stack + Grafana admin credentials from SSM |
| `cluster-secret-store.yaml` | ClusterSecretStore | cluster-scoped | Single ESO store for all namespaces |
| `ingress.yaml` | Ingress × 2 | argocd, monitoring | ALB rules for `argocd.*` and `grafana.*` |
| `todo.yaml` | Application | argocd | Todo app — references chart pushed by CI |

## Sync wave order

```
wave 0  lbc Application         — IngressClass + webhook CRDs land first
wave 0  eso Application         — ExternalSecret CRDs land first
wave 1  ClusterSecretStore      — needs ESO CRDs
wave 1  grafana ExternalSecret  — needs ClusterSecretStore
wave 2  Ingress (argocd+grafana)— needs LBC IngressClass
wave 3  todo Application        — needs LBC + ClusterSecretStore + ESO
```

## Updating the todo chart version

After CI pushes a new `charts/todo:<version>` to ECR, bump `todo.chartVersion` in `values.yaml` and push the platform chart. ArgoCD detects the new platform chart version (poll interval 3 min) and syncs the updated `todo` Application, which triggers a new `helm upgrade` of the todo release.

## Inputs (values.yaml)

| Key | Description |
|---|---|
| `global.ecrRegistry` | ECR registry hostname (`<account>.dkr.ecr.<region>.amazonaws.com`) |
| `global.region` | AWS region |
| `global.clusterName` | EKS cluster name — passed to LBC so it knows which cluster to watch |
| `ingress.groupName` | ALB IngressGroup name — all Ingresses share one ALB via this |
| `ingress.certificateArn` | ACM wildcard cert ARN for `*.alexanderkachar.com` |
| `ingress.argocdHost` / `grafanaHost` | Fully-qualified hostnames for the two platform UIs |
| `lbc.chartVersion` | Chart version pinned from `mirror-charts.sh` |
| `eso.chartVersion` | Chart version pinned from `mirror-charts.sh` |
| `prometheus.chartVersion` | Chart version pinned from `mirror-charts.sh` |
| `todo.chartVersion` | Chart version of the todo app to deploy |
| `todo.ssmPrefix` | SSM prefix where RDS connection params live |

## ArgoCD ECR auth

The platform chart is sourced by the root Application (`k8s/argocd-bootstrap/root-app.yaml`). ArgoCD authenticates to ECR using the `argocd-ecr-creds` Secret, which is seeded during bootstrap and kept fresh by the `ecr-creds-sync` CronJob (`k8s/argocd-bootstrap/ecr-creds-sync.yaml`).
