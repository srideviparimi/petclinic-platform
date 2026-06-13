variable "project" {
  description = "Project name used in repository naming"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment name (dev or prod)"
  type        = string
}

variable "service_names" {
  description = "List of service names to create ECR repositories for"
  type        = list(string)
}

variable "image_tag_mutability" {
  description = "Tag mutability: MUTABLE for dev (allows re-push), IMMUTABLE for prod"
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "tags" {
  description = "Additional tags to merge onto all resources"
  type        = map(string)
  default     = {}
}
