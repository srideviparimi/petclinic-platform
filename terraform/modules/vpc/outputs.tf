output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs (one per AZ)"
  value       = aws_subnet.public[*].id
}

output "eks_cluster_sg_id" {
  description = "EKS cluster (control plane) security group ID"
  value       = aws_security_group.eks_cluster.id
}

output "eks_node_sg_id" {
  description = "EKS worker node security group ID"
  value       = aws_security_group.eks_node.id
}

output "rds_sg_id" {
  description = "RDS security group ID (MySQL from EKS nodes only)"
  value       = aws_security_group.rds.id
}

output "alb_sg_id" {
  description = "ALB security group ID (HTTP/HTTPS from internet)"
  value       = aws_security_group.alb.id
}

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id # adjust to your actual resource address
}
