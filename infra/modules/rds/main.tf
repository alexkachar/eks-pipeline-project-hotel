locals {
  name             = "${var.project_name}-${var.environment}-postgres"
  ssm_param_prefix = "/${var.project_name}/rds"
}

# ---------------------------------------------------------------------------
# Dedicated CMK for RDS storage at rest. SSM SecureStrings are encrypted with
# the shared secrets module CMK, which is what External Secrets can decrypt.
# ---------------------------------------------------------------------------
resource "aws_kms_key" "rds" {
  description             = "RDS storage encryption for ${local.name}."
  enable_key_rotation     = true
  deletion_window_in_days = 7

  tags = { Name = "${local.name}-kms" }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.rds.key_id
}

# ---------------------------------------------------------------------------
# Master password. RDS Postgres forbids '/', '"', '@', and space in the
# master password; override_special restricts to a safe subset that also
# survives shell + SQL string round-trips.
# ---------------------------------------------------------------------------
resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}:?"
}

# ---------------------------------------------------------------------------
# Subnet group across the two DB subnets — neither has a default route, so
# Postgres traffic stays within the VPC.
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "this" {
  name       = local.name
  subnet_ids = var.db_subnet_ids
  tags       = { Name = local.name }
}

# ---------------------------------------------------------------------------
# Security group: ingress 5432 from the cluster SG only. No egress block —
# Terraform creates SGs with no default egress, which is what we want
# (Postgres doesn't initiate outbound connections).
# ---------------------------------------------------------------------------
resource "aws_security_group" "this" {
  name        = "${local.name}-sg"
  description = "Postgres: ingress 5432 from cluster nodes only; no egress."
  vpc_id      = var.vpc_id

  tags = { Name = "${local.name}-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "from_cluster" {
  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = var.cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "Postgres from EKS cluster nodes."

  tags = { Name = "${local.name}-from-cluster" }
}

# ---------------------------------------------------------------------------
# Postgres instance. Single-AZ, encrypted, private, no final snapshot —
# matches the portfolio teardown semantics from CLAUDE.md §6.6.
# ---------------------------------------------------------------------------
resource "aws_db_instance" "this" {
  identifier = local.name

  engine            = "postgres"
  engine_version    = var.engine_version
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage_gb
  storage_type      = "gp3"
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  db_name  = var.db_name
  username = var.master_username
  password = random_password.master.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false

  # Defer parameter-group / version changes to the next maintenance window
  # so a routine `terraform apply` doesn't trigger a surprise restart.
  apply_immediately          = false
  auto_minor_version_upgrade = false

  tags = { Name = local.name }
}

# ---------------------------------------------------------------------------
# SSM Parameter Store: secret + connection metadata grouped under one
# prefix so an ESO SecretStore can pull the whole bundle in one selector.
# ---------------------------------------------------------------------------
resource "aws_ssm_parameter" "master_password" {
  name   = "${local.ssm_param_prefix}/master-password"
  type   = "SecureString"
  key_id = var.ssm_kms_key_id
  value  = random_password.master.result

  tags = { Name = "${local.name}-master-password" }
}

resource "aws_ssm_parameter" "host" {
  name  = "${local.ssm_param_prefix}/host"
  type  = "String"
  value = aws_db_instance.this.address

  tags = { Name = "${local.name}-host" }
}

resource "aws_ssm_parameter" "port" {
  name  = "${local.ssm_param_prefix}/port"
  type  = "String"
  value = tostring(aws_db_instance.this.port)

  tags = { Name = "${local.name}-port" }
}

resource "aws_ssm_parameter" "database" {
  name  = "${local.ssm_param_prefix}/database"
  type  = "String"
  value = aws_db_instance.this.db_name

  tags = { Name = "${local.name}-database" }
}

resource "aws_ssm_parameter" "username" {
  name  = "${local.ssm_param_prefix}/username"
  type  = "String"
  value = var.master_username

  tags = { Name = "${local.name}-username" }
}
