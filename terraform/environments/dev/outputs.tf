# VPC outputs
output "vpc_id" {
  description = "Dev VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Dev public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "eks_cluster_sg_id" {
  description = "Dev EKS cluster security group ID"
  value       = module.vpc.eks_cluster_sg_id
}

output "eks_node_sg_id" {
  description = "Dev EKS node security group ID"
  value       = module.vpc.eks_node_sg_id
}

output "rds_sg_id" {
  description = "Dev RDS security group ID"
  value       = module.vpc.rds_sg_id
}

output "alb_sg_id" {
  description = "Dev ALB security group ID"
  value       = module.vpc.alb_sg_id
}

# EKS outputs
output "cluster_name" {
  description = "Dev EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Dev EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "Dev cluster CA certificate (base64)"
  value       = module.eks.cluster_ca_certificate
}

output "oidc_provider_arn" {
  description = "Dev OIDC provider ARN (for IRSA)"
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "Dev OIDC provider URL (for IRSA trust policies)"
  value       = module.eks.oidc_provider_url
}

output "node_role_arn" {
  description = "Dev EKS node IAM role ARN"
  value       = module.eks.node_role_arn
}

output "kubeconfig_command" {
  description = "Command to configure kubectl for dev cluster"
  value       = module.eks.kubeconfig_command
}

# ECR outputs
output "ecr_repository_urls" {
  description = "Map of service name to ECR repository URL (dev)"
  value       = module.ecr.repository_urls
}

output "ecr_repository_arns" {
  description = "Map of service name to ECR repository ARN (dev)"
  value       = module.ecr.repository_arns
}

# RDS outputs
output "rds_endpoint" {
  description = "Dev RDS instance hostname"
  value       = module.rds.endpoint
  sensitive   = true
}

output "rds_port" {
  description = "Dev RDS instance port"
  value       = module.rds.port
}

output "rds_instance_id" {
  description = "Dev RDS instance identifier"
  value       = module.rds.db_instance_id
}

output "rds_secret_arn" {
  description = "Dev RDS credentials secret ARN (Secrets Manager)"
  value       = module.rds.secret_arn
}
