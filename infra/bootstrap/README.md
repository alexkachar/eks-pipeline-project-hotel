# bootstrap

Creates the S3 bucket + DynamoDB table used as the Terraform backend for the root module.

Runs once with local state. Copy the `backend_block` output into `infra/backend.tf` afterward.

## Apply

```
cd infra/bootstrap
terraform init
terraform apply
```

## Inputs

| Name | Default |
|---|---|
| `region` | `us-east-1` |
| `bucket_prefix` | `tfstate` |
| `lock_table_name` | `tf-locks` |

## Outputs

- `bucket_name` — state bucket name (includes random suffix)
- `dynamodb_table_name` — lock table name
- `backend_block` — ready-to-paste backend config
