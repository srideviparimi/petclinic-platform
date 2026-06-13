# Karpenter module — provisions IAM roles, SQS queue, and EventBridge rules for Karpenter.
# Karpenter replaces Cluster Autoscaler for faster node provisioning. See ADR-0009.
# Prerequisites: EKS cluster (PETPLAT-12), OIDC provider.
# Implemented in: PETPLAT-14 series (E-14 Scaling & Cost Optimization).
