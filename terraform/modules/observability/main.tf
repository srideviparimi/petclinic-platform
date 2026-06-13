# Observability module — provisions AWS-side resources for the observability stack.
# In-cluster stack (Prometheus, Grafana, Loki, FluentBit, Zipkin, Alertmanager) is deployed
# via kubectl/Helm, not Terraform. This module handles any AWS resources (e.g. EBS volumes
# if needed, IAM roles for IRSA if required).
# Implemented in: PETPLAT-55 through PETPLAT-60.
