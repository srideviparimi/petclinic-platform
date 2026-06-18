variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name (dev or prod)"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name used in resource naming and tags"
  type        = string
  default     = "petclinic"
}

variable "domain_name" {
  description = "Apex domain name for the Route 53 hosted zone and ACM certificate (e.g. example.com)"
  type        = string
    default     = "petclinic-dev.click"
}

variable "alb_dns_name" {
  description = "ALB DNS name for the Route 53 alias record. Leave empty on the first apply (before the ingress creates the ALB). Re-apply with this value once the ALB is provisioned."
  type        = string
  default     = ""
}

variable "alb_zone_id" {
  description = "Route 53 hosted zone ID of the ALB (not the domain zone). Required alongside alb_dns_name. eu-central-1 ALBs use Z215JYRZR1TBD5."
  type        = string
  default     = ""

  validation {
    condition     = var.alb_zone_id == "" || can(regex("^Z[A-Z0-9]+$", var.alb_zone_id))
    error_message = "alb_zone_id must be empty or a valid Route 53 zone ID (e.g. Z215JYRZR1TBD5)."
  }
}
