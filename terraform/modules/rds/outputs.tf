output "endpoint" {
  description = "RDS instance hostname (without port)"
  value       = aws_db_instance.main.address
  sensitive   = true
}

output "port" {
  description = "RDS instance port"
  value       = aws_db_instance.main.port
}

output "db_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.main.id
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret holding RDS credentials (JSON: username, password)"
  value       = aws_secretsmanager_secret.rds_credentials.arn
}
