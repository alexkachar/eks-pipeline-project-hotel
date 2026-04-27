locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_kms_key" "ssm" {
  description             = "Encrypts SSM SecureString parameters consumed by External Secrets for ${local.name_prefix}."
  enable_key_rotation     = true
  deletion_window_in_days = 7

  tags = { Name = "${local.name_prefix}-ssm-secrets" }
}

resource "aws_kms_alias" "ssm" {
  name          = "alias/${local.name_prefix}-ssm-secrets"
  target_key_id = aws_kms_key.ssm.key_id
}

resource "random_password" "grafana_admin" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}:?"
}

resource "aws_ssm_parameter" "grafana_admin_password" {
  name   = "/${var.project_name}/grafana/admin-password"
  type   = "SecureString"
  key_id = aws_kms_key.ssm.id
  value  = random_password.grafana_admin.result

  tags = { Name = "${local.name_prefix}-grafana-admin-password" }
}
