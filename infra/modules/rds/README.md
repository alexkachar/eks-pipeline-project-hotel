# rds

Single-AZ Postgres 16 in the DB subnets. Connection details (and the master password) live in SSM Parameter Store under `/<project>/rds/*` so the future External Secrets Operator can project them into Kubernetes Secrets without ever touching git.

## Posture

- Private (`publicly_accessible = false`), single-AZ, no automated backups (portfolio teardown semantics).
- Storage encrypted with a dedicated CMK; the same CMK encrypts the `master-password` SSM SecureString. ESO will need `kms:Decrypt` on the CMK — `kms_key_arn` is exposed for that.
- Security group: ingress 5432 from the EKS cluster SG only. No egress rules — Postgres doesn't initiate outbound traffic.
- `skip_final_snapshot = true`, `deletion_protection = false`, so `terraform destroy` works in one shot.
- `apply_immediately = false` and `auto_minor_version_upgrade = false` — routine `terraform apply` cycles never trigger surprise restarts; planned changes wait for the maintenance window.

## SSM layout

| Parameter | Type | Purpose |
|---|---|---|
| `/<project>/rds/master-password` | `SecureString` | Master password, KMS-encrypted with the RDS CMK. |
| `/<project>/rds/host` | `String` | Endpoint hostname. |
| `/<project>/rds/port` | `String` | Port (5432). |
| `/<project>/rds/database` | `String` | DB name (`todo` by default). |
| `/<project>/rds/username` | `String` | Master username (`todo_admin` by default). |

## Inputs

`project_name`, `environment`, `vpc_id`, `db_subnet_ids`, `cluster_security_group_id`, `engine_version` (default `16.6`), `instance_class` (default `db.t4g.micro`), `allocated_storage_gb` (default `20`), `db_name` (default `todo`), `master_username` (default `todo_admin`).

## Outputs

`ssm_parameter_prefix`, `instance_endpoint` (sensitive), `kms_key_arn`, `security_group_id`.
