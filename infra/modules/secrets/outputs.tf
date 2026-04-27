output "kms_key_arn" {
  description = "CMK ARN used to encrypt SSM SecureStrings that ESO reads."
  value       = aws_kms_key.ssm.arn
}

output "kms_key_id" {
  description = "CMK key ID used by aws_ssm_parameter key_id inputs."
  value       = aws_kms_key.ssm.id
}

output "kms_alias" {
  description = "KMS alias for the shared SSM secrets key."
  value       = aws_kms_alias.ssm.name
}

output "grafana_admin_password_parameter_name" {
  description = "SSM SecureString parameter containing Grafana's admin password."
  value       = aws_ssm_parameter.grafana_admin_password.name
}
