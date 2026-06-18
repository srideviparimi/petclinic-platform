#!/usr/bin/env bash
# install-lb-controller.sh — Install the AWS Load Balancer Controller on EKS.
#
# Prerequisites:
#   - kubectl configured for the target cluster (aws eks update-kubeconfig ...)
#   - helm 3.x installed
#   - LB controller IRSA role created by Terraform (terraform output lb_controller_role_arn)
#
# Controller app version: v2.8.1
# Helm chart version:     1.8.1  (different numbering — chart 1.x = app v2.x)
#
# Usage:
#   export CLUSTER_NAME=petclinic-dev
#   export LB_CONTROLLER_ROLE_ARN=arn:aws:iam::<account>:role/petclinic-dev-lb-controller-role
#   export AWS_REGION=eu-central-1
#   export VPC_ID=vpc-<id>
#   bash scripts/install-lb-controller.sh

set -euo pipefail

: "${CLUSTER_NAME:?CLUSTER_NAME is required}"
: "${LB_CONTROLLER_ROLE_ARN:?LB_CONTROLLER_ROLE_ARN is required}"
: "${AWS_REGION:=eu-central-1}"
: "${VPC_ID:?VPC_ID is required}"

CONTROLLER_APP_VERSION="v2.8.1"
HELM_CHART_VERSION="1.8.1"

echo "==> Installing AWS Load Balancer Controller ${CONTROLLER_APP_VERSION} on cluster: ${CLUSTER_NAME}"

# ── Step 1: Install CRDs ───────────────────────────────────────────────────────
# Apply CRDs from the controller GitHub repo using the application version tag.
# Use the app version tag (v2.8.1), NOT the Helm chart version (1.8.1) — they
# use different numbering and the wrong tag will return a 404.

echo "==> Step 1: Installing CRDs from controller repo ${CONTROLLER_APP_VERSION}"

kubectl apply --server-side -f \
  "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${CONTROLLER_APP_VERSION}/config/crd/bases/elbv2.k8s.aws_ingressclassparams.yaml"

kubectl apply --server-side -f \
  "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${CONTROLLER_APP_VERSION}/config/crd/bases/elbv2.k8s.aws_targetgroupbindings.yaml"

echo "==> CRDs installed."

# ── Step 2: Add the EKS Helm chart repository ──────────────────────────────────

echo "==> Step 2: Adding eks Helm repo"
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

# ── Step 3: Install the controller via Helm ────────────────────────────────────
# The ServiceAccount is created by Helm and annotated with the IRSA role ARN.
# This annotation allows the pod to assume the role via OIDC.

echo "==> Step 3: Installing aws-load-balancer-controller chart ${HELM_CHART_VERSION}"

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version "${HELM_CHART_VERSION}" \
  --namespace kube-system \
  --set clusterName="${CLUSTER_NAME}" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${LB_CONTROLLER_ROLE_ARN}" \
  --set region="${AWS_REGION}" \
  --set vpcId="${VPC_ID}" \
  --wait \
  --timeout 5m

# ── Step 4: Verify ─────────────────────────────────────────────────────────────

echo "==> Step 4: Verifying controller deployment"
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=120s

echo ""
echo "==> AWS Load Balancer Controller ${CONTROLLER_APP_VERSION} installed successfully."
echo ""
echo "Next steps:"
echo "  1. Apply the Ingress manifest:"
echo "     kubectl apply -f k8s/base/ingress/ingress.yaml"
echo ""
echo "  2. Wait for ALB to be provisioned (1-2 min), then get its DNS name:"
echo "     kubectl get ingress petclinic-ingress -n petclinic-dev -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
echo ""
echo "  3. Set the ALB DNS name and zone ID in Terraform, then re-apply to create the Route 53 alias:"
echo "     # eu-central-1 ALB zone ID: Z215JYRZR1TBD5"
echo "     terraform -chdir=terraform/environments/dev apply \\"
echo "       -var='alb_dns_name=<alb-hostname>' \\"
echo "       -var='alb_zone_id=Z215JYRZR1TBD5'"
