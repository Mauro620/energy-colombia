output "endpoint" {
  value = aws_db_instance.principal.address
}

output "puerto" {
  value = aws_db_instance.principal.port
}

output "secreto_contrasena_arn" {
  description = "ARN del secreto con la contrasena maestra (no se expone la contrasena)"
  value       = aws_db_instance.principal.master_user_secret[0].secret_arn
}

output "security_group_id" {
  value = aws_security_group.db.id
}

output "db_subnet_group" {
  value = aws_db_subnet_group.principal.name
}

# Los usan los scripts de infra/aws (pitr.sh restaura con el mismo SG, subnet group y parameter group)
output "db_identifier" {
  value = aws_db_instance.principal.identifier
}

output "parameter_group" {
  value = aws_db_parameter_group.principal.name
}

output "db_name" {
  value = aws_db_instance.principal.db_name
}

output "proyecto" {
  value = local.nombre
}
