variable "project" {
  description = "Project name used in resource naming"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment name (dev or prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be 'dev' or 'prod'."
  }
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN for the IRSA trust policy principal (from eks module output)"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL without https:// prefix (used as condition key in IRSA trust policy)"
  type        = string
}

variable "node_role_arn" {
  description = "Node IAM role ARN for Karpenter-launched nodes (used for iam:PassRole and instance profile)"
  type        = string
}

variable "tags" {
  description = "Additional tags to merge onto all resources"
  type        = map(string)
  default     = {}
}
