variable "project" {
  description = "Project name used in resource naming"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment name (dev or prod)"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the RDS DB subnet group (public subnets)"
  type        = list(string)
}

variable "security_group_id" {
  description = "RDS security group ID (allows 3306 from EKS node SG only)"
  type        = string
}

variable "instance_class" {
  description = "RDS instance class (db.t4g.micro is free-tier eligible)"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum autoscale storage in GB"
  type        = number
  default     = 20
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment (false for cost optimization in learning env)"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Backup retention in days (7 for dev, 30 for prod)"
  type        = number
  default     = 7
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on deletion (true for dev, false for prod)"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to merge onto all resources"
  type        = map(string)
  default     = {}
}
