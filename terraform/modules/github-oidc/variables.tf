variable "project" {
  description = "Project name — used in resource names and tags"
  type        = string
  default     = "petclinic"
}

variable "app_repo" {
  description = "GitHub repository in '{owner}/{name}' format scoped in the OIDC subject claim (e.g., 'srideviparimi/spring-petclinic-microservices'). Only pushes from main branch of this repo are trusted."
  type        = string
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs to grant push access to. ecr:GetAuthorizationToken is always account-scoped (resource = '*'); all other push actions are restricted to these ARNs."
  type        = list(string)
}

variable "tags" {
  description = "Additional tags to merge onto all resources"
  type        = map(string)
  default     = {}
}
