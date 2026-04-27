# todo chart

Deploys the React frontend, Express backend, ALB ingress, and RDS connection
secret wiring for the todo app.

The backend reads database connection settings from a Kubernetes Secret named
`todo-backend-db`. External Secrets fills that Secret from SSM Parameter Store:

- `/<project_name>/rds/host`
- `/<project_name>/rds/port`
- `/<project_name>/rds/database`
- `/<project_name>/rds/username`
- `/<project_name>/rds/master-password`

The backend image includes SQL migrations under `apps/backend/migrations`.
The chart runs `npm run migrate` as an init container before starting the API.

Package and push:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com"
aws ecr get-login-password --region us-east-1 \
  | helm registry login --username AWS --password-stdin "$REGISTRY"
helm package apps/charts/todo -d /tmp
helm push /tmp/todo-0.1.0.tgz "oci://${REGISTRY}/charts"
```
