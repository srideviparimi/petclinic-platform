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

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── OpenAI API Key ───────────────────────────────────────────────────────────────
# Stores the GenAI service's OpenAI API key as a plaintext Secrets Manager secret.
# Value is accepted as a sensitive variable — never hardcoded.
# count = 0 when openai_api_key is empty (GenAI service is optional — defaults to
# the built-in "demo" mode when no key is configured).

resource "aws_secretsmanager_secret" "openai_api_key" {
  count = var.openai_api_key != "" ? 1 : 0

  name        = "${var.project}/${var.environment}/openai-api-key"
  description = "OpenAI API key for the ${local.name_prefix} genai-service"

  # Retain for 7 days before permanent deletion (allows accident recovery).
  recovery_window_in_days = 7

  tags = merge(local.common_tags, { Service = "genai-service" })
}

resource "aws_secretsmanager_secret_version" "openai_api_key" {
  count = var.openai_api_key != "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.openai_api_key[0].id
  secret_string = var.openai_api_key
}

# ── ESO IAM Policy ───────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "eso" {
  statement {
    sid    = "SecretsManagerRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.project}/*",
    ]
  }
}

resource "aws_iam_policy" "eso" {
  name        = "${local.name_prefix}-eso-policy"
  description = "External Secrets Operator read access to ${var.project}/* secrets"
  policy      = data.aws_iam_policy_document.eso.json

  tags = local.common_tags
}

# ── ESO IRSA Role ────────────────────────────────────────────────────────────────
# Trust policy scoped to the external-secrets-sa ServiceAccount in the
# external-secrets namespace. The ESO Helm chart or install manifest must
# create this ServiceAccount and annotate it with this role ARN.

resource "aws_iam_role" "eso" {
  name = "${local.name_prefix}-eso-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:sub" = "system:serviceaccount:external-secrets:external-secrets-sa"
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eso" {
  role       = aws_iam_role.eso.name
  policy_arn = aws_iam_policy.eso.arn
}
