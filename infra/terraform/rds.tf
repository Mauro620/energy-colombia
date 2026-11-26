resource "aws_db_parameter_group" "principal" {
  name        = "${local.nombre}-pg16"
  family      = "postgres16"
  description = "energia-db: replicacion logica, SSL obligatorio, log de consultas lentas"

  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot" # parametro estatico
  }

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "500" # ms
  }
}

resource "aws_db_instance" "principal" {
  identifier = local.nombre

  engine               = "postgres"
  engine_version       = var.engine_version
  instance_class       = "db.t4g.micro"
  parameter_group_name = aws_db_parameter_group.principal.name

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  # RDS crea y rota la contrasena en Secrets Manager: no pasa por el state ni por el repo
  manage_master_user_password = true

  multi_az               = false
  db_subnet_group_name   = aws_db_subnet_group.principal.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = true

  backup_retention_period = 1                     # el plan gratuito de AWS no admite mas; subir a 7 al pasar a plan de pago
  backup_window           = "07:00-08:00"         # 02:00-03:00 hora de Colombia (UTC-5)
  maintenance_window      = "sun:08:30-sun:09:30" # 03:30-04:30 hora de Colombia

  performance_insights_enabled          = true
  performance_insights_retention_period = 7 # retencion gratuita

  auto_minor_version_upgrade = false # evita deriva respecto de engine_version
  deletion_protection        = var.proteccion
  skip_final_snapshot        = var.omitir_snapshot_final
  final_snapshot_identifier  = var.omitir_snapshot_final ? null : "${local.nombre}-final"
}
