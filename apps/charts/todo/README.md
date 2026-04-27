# todo chart

Deploys the React frontend, Express backend, ALB ingress, and RDS connection
secret wiring for `todo.alexanderkachar.com`.

The backend reads database connection settings from a Kubernetes Secret named
`todo-backend-db`. External Secrets fills that Secret from SSM Parameter Store:

- `/project-hotel/rds/host`
- `/project-hotel/rds/port`
- `/project-hotel/rds/database`
- `/project-hotel/rds/username`
- `/project-hotel/rds/master-password`

The backend image includes SQL migrations under `apps/backend/migrations`.
The chart runs `npm run migrate` as an init container before starting the API.

Package and push:

```bash
helm package apps/charts/todo -d /tmp
helm push /tmp/todo-0.1.0.tgz oci://038526103886.dkr.ecr.us-east-1.amazonaws.com/charts
```
