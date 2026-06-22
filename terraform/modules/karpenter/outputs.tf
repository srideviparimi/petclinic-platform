output "karpenter_role_arn" {
  description = "Karpenter controller IRSA role ARN — annotate the karpenter ServiceAccount with this"
  value       = aws_iam_role.karpenter.arn
}

output "karpenter_queue_name" {
  description = "SQS interruption queue name — pass to Karpenter Helm chart as settings.interruptionQueue"
  value       = aws_sqs_queue.karpenter_interruption.name
}

output "karpenter_instance_profile_name" {
  description = "Instance profile name for Karpenter-launched nodes — referenced in EC2NodeClass CRD spec.instanceProfile"
  value       = aws_iam_instance_profile.karpenter_node.name
}
