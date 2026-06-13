# VPC module outputs — defined here as the interface contract, implemented in PETPLAT-6 and PETPLAT-8.

# output "vpc_id" {
#   description = "The ID of the VPC"
#   value       = aws_vpc.main.id
# }

# output "public_subnet_ids" {
#   description = "List of public subnet IDs"
#   value       = aws_subnet.public[*].id
# }

# output "eks_cluster_sg_id" {
#   description = "EKS cluster security group ID"
#   value       = aws_security_group.eks_cluster.id
# }

# output "eks_node_sg_id" {
#   description = "EKS node security group ID"
#   value       = aws_security_group.eks_node.id
# }

# output "rds_sg_id" {
#   description = "RDS security group ID"
#   value       = aws_security_group.rds.id
# }

# output "alb_sg_id" {
#   description = "ALB security group ID"
#   value       = aws_security_group.alb.id
# }
