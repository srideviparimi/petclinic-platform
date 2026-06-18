variable "domain_name" {
  description = "Apex domain name for the Route 53 hosted zone (e.g. example.com)"
  type        = string

}

variable "project" {
  description = "Project name used in resource naming and tags"
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
  description = "EKS cluster name — passed to the LB controller Helm values"
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN for the LB controller IRSA trust policy"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL without https:// prefix (for IRSA trust policy conditions)"
  type        = string
}

variable "record_name" {
  description = "Subdomain prefix for the Route 53 A alias record (e.g. 'petclinic-dev'). Empty string targets the apex domain."
  type        = string
  default     = ""
}

variable "alb_dns_name" {
  description = "ALB DNS hostname for the Route 53 alias record. Leave empty on first apply (before the ALB is created by the ingress controller)."
  type        = string
  default     = ""
}

variable "alb_zone_id" {
  description = "Route 53 hosted zone ID of the ALB (not the domain zone). Required when alb_dns_name is set. Each AWS region has a fixed zone ID for ALBs."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to merge onto all resources"
  type        = map(string)
  default     = {}
}
