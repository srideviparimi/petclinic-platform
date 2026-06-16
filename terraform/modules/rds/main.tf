locals {
  name_prefix = "${var.project}-${var.environment}"
}

resource "random_password" "master" {
  length           = 16
  special          = true
  override_special = "!#$%&()-_=+[]<>:?"
}

resource "aws_secretsmanager_secret" "rds_credentials" {
  name                    = "petclinic/${var.environment}/rds-credentials"
  description             = "RDS master credentials for ${local.name_prefix}-mysql"
  recovery_window_in_days = 0

  tags = merge(var.tags, {
    Name = "petclinic/${var.environment}/rds-credentials"
  })
}

resource "aws_secretsmanager_secret_version" "rds_credentials" {
  secret_id = aws_secretsmanager_secret.rds_credentials.id
  secret_string = jsonencode({
    username = "petclinic"
    password = random_password.master.result
  })
}

resource "aws_db_subnet_group" "main" {
  name        = "${local.name_prefix}-rds-subnet-group"
  description = "RDS subnet group for ${local.name_prefix}"
  subnet_ids  = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-rds-subnet-group"
  })
}

resource "aws_db_parameter_group" "main" {
  name        = "${local.name_prefix}-mysql8"
  family      = "mysql8.0"
  description = "MySQL 8.0 parameter group for ${local.name_prefix}"

  parameter {
    name         = "character_set_server"
    value        = "utf8mb4"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "collation_server"
    value        = "utf8mb4_unicode_ci"
    apply_method = "pending-reboot"
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-mysql8"
  })
}

resource "aws_db_instance" "main" {
  identifier = "${local.name_prefix}-mysql"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.instance_class

  db_name  = "petclinic"
  username = "petclinic"
  password = random_password.master.result

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp2"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.security_group_id]
  parameter_group_name   = aws_db_parameter_group.main.name
  publicly_accessible    = false

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_period

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.name_prefix}-mysql-final-snapshot"
  deletion_protection       = var.deletion_protection

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-mysql"
  })

  depends_on = [aws_secretsmanager_secret_version.rds_credentials]
}
