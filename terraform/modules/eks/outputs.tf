# EKS module outputs — defined here as the interface contract, implemented in PETPLAT-12 and PETPLAT-13.

# output "cluster_name" {
#   description = "EKS cluster name"
#   value       = aws_eks_cluster.main.name
# }

# output "cluster_endpoint" {
#   description = "EKS API server endpoint"
#   value       = aws_eks_cluster.main.endpoint
# }

# output "cluster_ca_certificate" {
#   description = "Cluster CA certificate (base64 encoded)"
#   value       = aws_eks_cluster.main.certificate_authority[0].data
# }

# output "oidc_provider_arn" {
#   description = "OIDC provider ARN for IRSA"
#   value       = aws_iam_openid_connect_provider.eks.arn
# }

# output "oidc_provider_url" {
#   description = "OIDC provider URL (without https://)"
#   value       = trimprefix(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://")
# }

# output "node_group_name" {
#   description = "Managed node group name"
#   value       = aws_eks_node_group.main.node_group_name
# }

# output "node_role_arn" {
#   description = "Node IAM role ARN"
#   value       = aws_iam_role.node.arn
# }
