locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags,
  )
}

# ── ECR Repositories (one per service) ────────────────────────────────────────

# ECR Private repositories are always private — there is no S3-style public
# access block because ECR Private (aws_ecr_repository) cannot be made public.
# ECR Public (aws_ecrpublic_repository) is a separate resource and service.
# Security model:
#   Pulls  — EKS nodes use AmazonEC2ContainerRegistryReadOnly (node IAM role).
#   Pushes — CI uses a dedicated OIDC role (created in E-10, PETPLAT-52)
#            with ecr:PutImage and related actions scoped to these repos.
# An explicit aws_ecr_repository_policy resource is deferred until the CI role
# ARN is known (E-10). Add it then to restrict pushes to that role only.

resource "aws_ecr_repository" "services" {
  for_each = toset(var.service_names)

  name                 = "${local.name_prefix}/${each.key}"
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = true
  }

  # AES256 = AWS-managed default KMS key (aws/ecr). Sufficient for this project.
  # Switch to a CMK via kms_key_id if cross-account access or key rotation is needed.
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, { Service = each.key })
}

# ── Lifecycle Policies ─────────────────────────────────────────────────────────
# Rule 1: expire untagged images after 7 days (storage cost control)
# Rule 2: keep at most 10 tagged images per repo (prune old builds)
# Lower rulePriority numbers are evaluated first.

resource "aws_ecr_lifecycle_policy" "services" {
  for_each = toset(var.service_names)

  repository = aws_ecr_repository.services[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
