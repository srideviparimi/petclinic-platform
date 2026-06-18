output "openai_secret_arn" {
  description = "Secrets Manager ARN for the OpenAI API key (empty string when openai_api_key variable is not set)"
  value       = var.openai_api_key != "" ? aws_secretsmanager_secret.openai_api_key[0].arn : ""
  sensitive   = true
}

output "eso_role_arn" {
  description = "IRSA role ARN for External Secrets Operator (annotate the external-secrets-sa ServiceAccount with this)"
  value       = aws_iam_role.eso.arn
}
