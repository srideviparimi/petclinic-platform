#!/usr/bin/env bash
# install-eso.sh — Install External Secrets Operator on EKS and configure AWS auth.
#
# Prerequisites:
#   - kubectl configured for the target cluster
#   - Terraform outputs available (ESO_ROLE_ARN)
#   - AWS CLI configured with sufficient permissions
#
# Usage:
#   ESO_ROLE_ARN=$(terraform -chdir=terraform/environments/dev output -raw eso_role_arn)
#   ./scripts/install-eso.sh

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────────
ESO_VERSION="${ESO_VERSION:-0.10.5}"
ESO_NAMESPACE="external-secrets"
ESO_SA_NAME="external-secrets-sa"
ESO_HELM_RELEASE="external-secrets"
ESO_HELM_REPO="https://charts.external-secrets.io"
REGION="${AWS_REGION:-eu-central-1}"

if [[ -z "${ESO_ROLE_ARN:-}" ]]; then
  echo "ERROR: ESO_ROLE_ARN is not set."
  echo "  Run: export ESO_ROLE_ARN=\$(terraform -chdir=terraform/environments/dev output -raw eso_role_arn)"
  exit 1
fi

echo "==> Installing External Secrets Operator v${ESO_VERSION}"
echo "    Namespace : ${ESO_NAMESPACE}"
echo "    ESO IRSA  : ${ESO_ROLE_ARN}"
echo "    Region    : ${REGION}"
echo ""

# ── Step 1: Create namespace ─────────────────────────────────────────────────────
echo "==> Step 1: Create ${ESO_NAMESPACE} namespace"
kubectl create namespace "${ESO_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# ── Step 2: Add Helm repo and install ESO ────────────────────────────────────────
echo ""
echo "==> Step 2: Add External Secrets Helm repo"
helm repo add external-secrets "${ESO_HELM_REPO}" --force-update
helm repo update external-secrets

echo ""
echo "==> Step 3: Install ESO via Helm (chart version ${ESO_VERSION})"
helm upgrade --install "${ESO_HELM_RELEASE}" external-secrets/external-secrets \
  --namespace "${ESO_NAMESPACE}" \
  --version "${ESO_VERSION}" \
  --set installCRDs=true \
  --set serviceAccount.name="${ESO_SA_NAME}" \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${ESO_ROLE_ARN}" \
  --wait \
  --timeout 5m

# ── Step 4: Verify ESO pods are running ──────────────────────────────────────────
echo ""
echo "==> Step 4: Verify ESO pods"
kubectl rollout status deployment/external-secrets -n "${ESO_NAMESPACE}" --timeout=120s
kubectl rollout status deployment/external-secrets-webhook -n "${ESO_NAMESPACE}" --timeout=120s
kubectl rollout status deployment/external-secrets-cert-controller -n "${ESO_NAMESPACE}" --timeout=120s

# ── Step 5: Apply ClusterSecretStore ─────────────────────────────────────────────
echo ""
echo "==> Step 5: Apply ClusterSecretStore (aws-secrets-manager)"
kubectl apply -f k8s/base/external-secrets/cluster-secret-store.yaml

echo ""
echo "==> ESO installation complete."
echo ""
echo "Next steps:"
echo "  1. Apply ExternalSecrets for your namespaces:"
echo "     kubectl apply -f k8s/base/external-secrets/rds-credentials.yaml"
echo "     kubectl apply -f k8s/base/external-secrets/openai-api-key.yaml"
echo "  2. Verify secrets are synced:"
echo "     kubectl get externalsecret -n petclinic-dev"
echo "     kubectl get secret rds-credentials -n petclinic-dev"
echo "     kubectl get secret openai-api-key -n petclinic-dev"
