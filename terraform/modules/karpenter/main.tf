data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name = "${var.project}-${var.environment}"

  # Extract role name from ARN (last path segment) for the instance profile role reference.
  # ARN format: arn:aws:iam::ACCOUNT:role/NAME
  node_role_name = element(split("/", var.node_role_arn), length(split("/", var.node_role_arn)) - 1)

  tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# IRSA role — Karpenter controller
# Trust policy uses OIDC provider from EKS module outputs — no hardcoded values.
# ─────────────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "karpenter_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:karpenter"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter" {
  name               = "${local.name}-karpenter-role"
  assume_role_policy = data.aws_iam_policy_document.karpenter_trust.json
  description        = "Karpenter controller IRSA role for ${local.name} cluster"
  tags               = local.tags
}

data "aws_iam_policy_document" "karpenter_controller" {
  # EC2: node provisioning, fleet management, launch template lifecycle
  statement {
    sid       = "EC2NodeManagement"
    effect    = "Allow"
    actions   = ["ec2:*"]
    resources = ["*"]
  }

  # IAM: PassRole scoped to the node IAM role ONLY — NOT "*".
  # Without this scope, Karpenter could be used to escalate privileges
  # by passing arbitrary roles to new EC2 instances.
  statement {
    sid       = "IamPassRoleToNodeRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [var.node_role_arn]
  }

  # SSM: AMI ID lookup via AWS-managed parameter store paths
  statement {
    sid       = "SsmAmiLookup"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:*:*:parameter/aws/service/*"]
  }

  # Pricing: spot price history and on-demand pricing for bin-packing decisions
  statement {
    sid       = "PricingLookup"
    effect    = "Allow"
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }

  # SQS: interruption queue — scoped to this environment's queue only
  statement {
    sid       = "InterruptionQueueAccess"
    effect    = "Allow"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.karpenter_interruption.arn]
  }

  # EKS: cluster metadata — scoped to this specific cluster
  statement {
    sid       = "EksClusterMetadata"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:aws:eks:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"]
  }
}

resource "aws_iam_policy" "karpenter_controller" {
  name        = "${local.name}-karpenter-controller-policy"
  description = "IAM policy for Karpenter controller on ${local.name}"
  policy      = data.aws_iam_policy_document.karpenter_controller.json
  tags        = local.tags
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  role       = aws_iam_role.karpenter.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}

# ─────────────────────────────────────────────────────────────────────────────
# Instance profile — attached to every node Karpenter provisions.
# Name MUST follow: petclinic-{env}-karpenter-node-profile
# This exact name is referenced in the EC2NodeClass CRD (spec.instanceProfile).
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_instance_profile" "karpenter_node" {
  name = "${local.name}-karpenter-node-profile"
  role = local.node_role_name
  tags = local.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# SQS interruption queue
# 20-minute visibility timeout gives Karpenter time to process before re-delivery.
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_sqs_queue" "karpenter_interruption" {
  name                       = "${local.name}-karpenter-interruption"
  message_retention_seconds  = 300
  visibility_timeout_seconds = 1200
  sqs_managed_sse_enabled    = true

  tags = local.tags
}

# Queue resource policy — EventBridge MUST be allowed to publish here.
# Without this policy, interruption events arrive at EventBridge but are dropped
# before reaching the queue, so Karpenter never handles spot terminations.
data "aws_iam_policy_document" "karpenter_queue" {
  statement {
    sid       = "AllowEventBridgePublish"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.karpenter_interruption.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
  }
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.id
  policy    = data.aws_iam_policy_document.karpenter_queue.json
}

# ─────────────────────────────────────────────────────────────────────────────
# EventBridge rules — 4 EC2/Health events routed to the interruption queue
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name        = "${local.name}-karpenter-spot-interruption"
  description = "EC2 spot instance 2-minute interruption warning to Karpenter"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "spot_interruption" {
  rule      = aws_cloudwatch_event_rule.spot_interruption.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_rule" "rebalance_recommendation" {
  name        = "${local.name}-karpenter-rebalance"
  description = "EC2 instance rebalance recommendation to Karpenter"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "rebalance_recommendation" {
  rule      = aws_cloudwatch_event_rule.rebalance_recommendation.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_rule" "instance_state_change" {
  name        = "${local.name}-karpenter-state-change"
  description = "EC2 instance state-change notification to Karpenter"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "instance_state_change" {
  rule      = aws_cloudwatch_event_rule.instance_state_change.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_rule" "scheduled_change" {
  name        = "${local.name}-karpenter-scheduled-change"
  description = "AWS Health scheduled EC2 maintenance events to Karpenter"

  event_pattern = jsonencode({
    source      = ["aws.health"]
    detail-type = ["AWS Health Event"]
    detail = {
      service           = ["EC2"]
      eventTypeCategory = ["scheduledChange"]
    }
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "scheduled_change" {
  rule      = aws_cloudwatch_event_rule.scheduled_change.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}
