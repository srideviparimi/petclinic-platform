output "zone_id" {
  description = "Route 53 hosted zone ID"
  value       = data.aws_route53_zone.main.zone_id
}

output "name_servers" {
  description = "Route 53 name servers for the hosted zone (used to delegate from registrar)"
  value       = data.aws_route53_zone.main.name_servers
}

output "certificate_arn" {
  description = "ACM wildcard certificate ARN (validated, ready to attach to ALB)"
  value       = aws_acm_certificate_validation.main.certificate_arn
}

output "lb_controller_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller (annotate the ServiceAccount with this)"
  value       = aws_iam_role.lb_controller.arn
}
