output "role_arn" {
  description = "ARN of the GitHub Actions IAM role — set this as the AWS_ROLE_ARN GitHub Secret in the app repo"
  value       = aws_iam_role.github_actions.arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider (token.actions.githubusercontent.com)"
  value       = aws_iam_openid_connect_provider.github.arn
}
