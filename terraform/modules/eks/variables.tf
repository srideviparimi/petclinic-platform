variable "project" {
  description = "Project name used in resource naming"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment name (dev or prod)"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.32"
}

variable "subnet_ids" {
  description = "Public subnet IDs for EKS cluster and node group"
  type        = list(string)
}

variable "cluster_sg_id" {
  description = "Security group ID for the EKS cluster control plane"
  type        = string
}

variable "node_sg_id" {
  description = "Security group ID for EKS worker nodes"
  type        = string
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group"
  type        = list(string)
  default     = ["t4g.small"]
}

variable "node_ami_type" {
  description = "AMI type for EKS nodes (AL2_ARM_64 for Graviton)"
  type        = string
  default     = "AL2_ARM_64"
}

variable "node_min_size" {
  description = "Minimum number of nodes in the managed node group"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of nodes in the managed node group"
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Desired number of nodes in the managed node group"
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "EBS root disk size in GB for each node"
  type        = number
  default     = 20
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to reach the EKS public API endpoint. Default allows all — restrict to known admin CIDRs in a hardened environment."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "admin_iam_principal_arn" {
  description = "IAM principal ARN to grant cluster-admin access via EKS access entry. Defaults to the identity running Terraform."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags to merge onto all resources"
  type        = map(string)
  default     = {}
}
