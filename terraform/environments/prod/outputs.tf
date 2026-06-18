# VPC outputs
output "vpc_id" {
  description = "Prod VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Prod public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "eks_cluster_sg_id" {
  description = "Prod EKS cluster security group ID"
  value       = module.vpc.eks_cluster_sg_id
}

output "eks_node_sg_id" {
  description = "Prod EKS node security group ID"
  value       = module.vpc.eks_node_sg_id
}

output "rds_sg_id" {
  description = "Prod RDS security group ID"
  value       = module.vpc.rds_sg_id
}

output "alb_sg_id" {
  description = "Prod ALB security group ID"
  value       = module.vpc.alb_sg_id
}

# EKS outputs
output "cluster_name" {
  description = "Prod EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Prod EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "Prod cluster CA certificate (base64)"
  value       = module.eks.cluster_ca_certificate
}

output "oidc_provider_arn" {
  description = "Prod OIDC provider ARN (for IRSA)"
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "Prod OIDC provider URL (for IRSA trust policies)"
  value       = module.eks.oidc_provider_url
}

output "node_role_arn" {
  description = "Prod EKS node IAM role ARN"
  value       = module.eks.node_role_arn
}

output "kubeconfig_command" {
  description = "Command to configure kubectl for prod cluster"
  value       = module.eks.kubeconfig_command
}

# ECR outputs
output "ecr_repository_urls" {
  description = "Map of service name to ECR repository URL (prod)"
  value       = module.ecr.repository_urls
}

output "ecr_repository_arns" {
  description = "Map of service name to ECR repository ARN (prod)"
  value       = module.ecr.repository_arns
}

# RDS outputs
output "rds_endpoint" {
  description = "Prod RDS instance hostname"
  value       = module.rds.endpoint
  sensitive   = true
}

output "rds_port" {
  description = "Prod RDS instance port"
  value       = module.rds.port
}

output "rds_instance_id" {
  description = "Prod RDS instance identifier"
  value       = module.rds.db_instance_id
}

output "rds_secret_arn" {
  description = "Prod RDS credentials secret ARN (Secrets Manager)"
  value       = module.rds.secret_arn
}

# DNS outputs
output "hosted_zone_id" {
  description = "Prod Route 53 hosted zone ID"
  value       = module.dns.zone_id
}

output "certificate_arn" {
  description = "Prod ACM wildcard certificate ARN (attach to ALB via Ingress annotation)"
  value       = module.dns.certificate_arn
}

output "lb_controller_role_arn" {
  description = "Prod AWS Load Balancer Controller IRSA role ARN (annotate the Helm ServiceAccount with this)"
  value       = module.dns.lb_controller_role_arn
}
