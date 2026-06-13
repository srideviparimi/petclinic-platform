# ECR module — provisions private ECR repositories for all 8 microservices.
# Uses aws_ecr_repository with lifecycle policies, scan-on-push, and configurable tag immutability.
# MUTABLE for dev, IMMUTABLE for prod. Lifecycle: keep last 10 images.
# Implemented in: PETPLAT-18 (repositories), PETPLAT-19 (lifecycle + immutability).
