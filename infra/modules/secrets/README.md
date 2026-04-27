# secrets

Shared SSM secret encryption for values that Kubernetes reads through External Secrets Operator.

## Resources

- A dedicated KMS CMK and alias for SSM SecureString parameters.
- A generated Grafana admin password at `/<project>/grafana/admin-password`.

RDS still has its own storage CMK, but its master-password SSM parameter uses this shared SSM key so the External Secrets role can decrypt one scoped key instead of depending on database module internals.

## Inputs

`project_name`, `environment`.

## Outputs

`kms_key_arn`, `kms_key_id`, `kms_alias`, `grafana_admin_password_parameter_name`.
