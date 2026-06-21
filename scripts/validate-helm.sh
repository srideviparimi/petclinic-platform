
#!/usr/bin/env bash
# Validates the generic Helm chart for all 8 Petclinic services.
# For each service × environment: helm lint, helm template, kubectl apply --dry-run=client
# Usage: ./scripts/validate-helm.sh [service] [env]
#   No args: validates all 8 services against both envs
#   service: one of config-server, discovery-server, api-gateway, customers-service,
#            visits-service, vets-service, genai-service, admin-server
#   env: dev | prod

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHART_DIR="${SCRIPT_DIR}/../helm/petclinic-service"
VALUES_DIR="${SCRIPT_DIR}/../helm-values"

SERVICES=(
  config-server
  discovery-server
  api-gateway
  customers-service
  visits-service
  vets-service
  genai-service
  admin-server
)
ENVS=(dev prod)

LINT_PASS=0
LINT_FAIL=0
TMPL_PASS=0
TMPL_FAIL=0
DRY_PASS=0
DRY_FAIL=0
DRY_SKIP=0
ERRORS=()

green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
red()   { printf '\033[0;31m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[0;33m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

# Check cluster connectivity once
CLUSTER_REACHABLE=false
if kubectl cluster-info --request-timeout=3s >/dev/null 2>&1; then
  CLUSTER_REACHABLE=true
fi

run_validation() {
  local svc="$1"
  local env="$2"
  local ns="petclinic-${env}"
  local label="${svc}/${env}"
  local tmp
  tmp=$(mktemp)

  bold "=== ${label} ==="

  # 1. helm lint
  printf "  helm lint       ... "
  local lint_out
  if lint_out=$(helm lint "${CHART_DIR}" \
       -f "${VALUES_DIR}/${svc}.yaml" \
       -f "${VALUES_DIR}/${env}.yaml" \
       --namespace "${ns}" \
       --strict 2>&1); then
    green "OK"
    LINT_PASS=$((LINT_PASS + 1))
  else
    red "FAILED"
    echo "${lint_out}"
    LINT_FAIL=$((LINT_FAIL + 1))
    ERRORS+=("${label}: helm lint failed")
    rm -f "${tmp}"
    return
  fi

  # 2. helm template
  printf "  helm template   ... "
  if helm template "${svc}" "${CHART_DIR}" \
       -f "${VALUES_DIR}/${svc}.yaml" \
       -f "${VALUES_DIR}/${env}.yaml" \
       --namespace "${ns}" \
       > "${tmp}" 2>&1; then
    # Count rendered resources
    local count
    count=$(grep -c '^kind:' "${tmp}" || true)
    green "OK (${count} resources)"
    TMPL_PASS=$((TMPL_PASS + 1))
  else
    red "FAILED"
    cat "${tmp}"
    TMPL_FAIL=$((TMPL_FAIL + 1))
    ERRORS+=("${label}: helm template failed")
    rm -f "${tmp}"
    return
  fi

  # 3. kubectl apply --dry-run=client
  printf "  kubectl dry-run ... "
  if [[ "${CLUSTER_REACHABLE}" == "false" ]]; then
    yellow "SKIP (no cluster)"
    DRY_SKIP=$((DRY_SKIP + 1))
  else
    local dry_out
    if dry_out=$(kubectl apply --dry-run=client -f "${tmp}" 2>&1); then
      green "OK"
      DRY_PASS=$((DRY_PASS + 1))
    else
      red "FAILED"
      echo "${dry_out}"
      DRY_FAIL=$((DRY_FAIL + 1))
      ERRORS+=("${label}: kubectl dry-run failed")
    fi
  fi

  rm -f "${tmp}"
}

# Parse optional args
TARGET_SVC="${1:-all}"
TARGET_ENV="${2:-all}"

if [[ "${CLUSTER_REACHABLE}" == "false" ]]; then
  yellow "NOTE: No cluster connection — kubectl dry-run steps will be skipped."
  yellow "      Connect to EKS first: aws eks update-kubeconfig --name petclinic-dev --region eu-central-1"
  echo ""
fi

for svc in "${SERVICES[@]}"; do
  [[ "${TARGET_SVC}" != "all" && "${TARGET_SVC}" != "${svc}" ]] && continue
  for env in "${ENVS[@]}"; do
    [[ "${TARGET_ENV}" != "all" && "${TARGET_ENV}" != "${env}" ]] && continue
    run_validation "${svc}" "${env}"
  done
done

echo ""
bold "Results:"
echo "  helm lint:    ${LINT_PASS} passed, ${LINT_FAIL} failed"
echo "  helm template:${TMPL_PASS} passed, ${TMPL_FAIL} failed"
echo "  kubectl drrun:${DRY_PASS} passed, ${DRY_FAIL} failed, ${DRY_SKIP} skipped (no cluster)"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  red "Failures:"
  for e in "${ERRORS[@]}"; do
    red "  - ${e}"
  done
  exit 1
fi

if [[ $((LINT_FAIL + TMPL_FAIL + DRY_FAIL)) -eq 0 ]]; then
  green "All validations passed."
fi
