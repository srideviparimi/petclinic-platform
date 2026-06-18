variable "project" {
  description = "Project name used in secret naming and resource naming"
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

variable "openai_api_key" {
  description = "OpenAI API key for the GenAI service — passed as a sensitive variable, never hardcoded"
  type        = string
  sensitive   = true
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN from the EKS module (for ESO IRSA trust policy)"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL without https:// prefix (for ESO IRSA trust policy conditions)"
  type        = string
}

variable "tags" {
  description = "Additional tags to merge onto all resources"
  type        = map(string)
  default     = {}
}
