# ECR module outputs — defined here as the interface contract, implemented in PETPLAT-18.

# output "repository_urls" {
#   description = "Map of service_name to ECR repository URL"
#   value       = { for name, repo in aws_ecr_repository.services : name => repo.repository_url }
# }

# output "repository_arns" {
#   description = "Map of service_name to ECR repository ARN"
#   value       = { for name, repo in aws_ecr_repository.services : name => repo.arn }
# }
