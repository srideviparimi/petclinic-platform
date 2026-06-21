locals {
  name_prefix = "${var.project}-github-actions"

  common_tags = merge(
    {
      Project   = var.project
      ManagedBy = "terraform"
    },
    var.tags,
  )
}

# ── GitHub Actions OIDC Provider ──────────────────────────────────────────────
# One provider per AWS account (not per environment). Allows GitHub Actions
# runners to exchange a short-lived OIDC token for temporary AWS credentials
# — no long-lived access keys stored in GitHub Secrets.

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]

  tags = local.common_tags
}

# ── ECR Push Policy ────────────────────────────────────────────────────────────
# ecr:GetAuthorizationToken is account-level and cannot be scoped to a repo ARN.
# All other ECR write actions are restricted to the repository ARNs provided.

data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "ECRAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_policy" "ecr_push" {
  name        = "${local.name_prefix}-ecr-push-policy"
  description = "Allows GitHub Actions to push images to ECR — granted to the OIDC-federated role only"
  policy      = data.aws_iam_policy_document.ecr_push.json

  tags = local.common_tags
}

# ── GitHub Actions IAM Role ────────────────────────────────────────────────────
# Trust policy is pinned to the app repo + main branch — not a wildcard subject.
# Action must be sts:AssumeRoleWithWebIdentity (OIDC federation).
# The build workflow runs in the app repo context, so the subject references
# the app repo (srideviparimi/spring-petclinic-microservices), NOT the platform repo.

resource "aws_iam_role" "github_actions" {
  name = "${local.name_prefix}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.app_repo}:ref:refs/heads/main"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecr_push" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.ecr_push.arn
}
