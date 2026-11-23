# -----------------------------------------------------------------------------
# RDS PostgreSQL in the isolated data subnets.
#   - Not publicly accessible, only reachable from the backend security group
#   - Storage encrypted, TLS enforced (rds.force_ssl = 1)
#   - Master password generated and stored by RDS in Secrets Manager
#     (never appears in code, variables, or Terraform state)
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = var.data_subnet_ids

  tags = { Name = "${var.name}-db" }
}

resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name}-pg${var.engine_major_version}-"
  family      = "postgres${var.engine_major_version}"
  description = "Hardened parameters for ${var.name}"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot" # as stored by AWS; avoids a perpetual diff (applied at DB creation)
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name}-postgres"
  engine         = "postgres"
  engine_version = var.engine_major_version
  instance_class = var.instance_class

  db_name                     = var.database_name
  username                    = var.master_username
  manage_master_user_password = true # RDS generates + stores the secret in Secrets Manager

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  multi_az               = var.multi_az
  port                   = var.port
  ca_cert_identifier     = "rds-ca-rsa2048-g1"

  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql", "upgrade"]

  backup_retention_period    = var.backup_retention_days
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true
  apply_immediately          = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-postgres-final"

  tags = { Name = "${var.name}-postgres" }
}
