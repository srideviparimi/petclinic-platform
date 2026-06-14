#!/usr/bin/env bash
# build-push.sh — Build ARM64 Docker images and push to ECR.
#
# Uses Maven to compile JARs, then docker buildx for linux/arm64 images.
# Does NOT use the Maven buildDocker profile — JAR build and image build are
# kept separate so the Dockerfile and build args are fully explicit.
#
# Usage:
#   ./scripts/build-push.sh --env dev --tag v1.0.0 [--app-dir ../spring-petclinic-microservices]
#   ./scripts/build-push.sh --env dev              # tag defaults to short git SHA
#   ./scripts/build-push.sh --env dev --services "config-server api-gateway"
#
# Prerequisites:
#   - AWS CLI configured with ECR push permissions
#   - Docker with buildx + QEMU (for ARM64 cross-compilation on x86 hosts)
#   - Java 17, Maven wrapper (./mvnw) in the app repo

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${PLATFORM_DIR}/../spring-petclinic-microservices"
REGION="eu-central-1"
ENV=""
TAG=""
SERVICES=""  # empty = build all 8

# ── Service definitions ───────────────────────────────────────────────────────
# Format: "ecr-repo-name:maven-module-dir:port"

declare -A SERVICE_MODULE=(
  ["config-server"]="spring-petclinic-config-server"
  ["discovery-server"]="spring-petclinic-discovery-server"
  ["api-gateway"]="spring-petclinic-api-gateway"
  ["customers-service"]="spring-petclinic-customers-service"
  ["visits-service"]="spring-petclinic-visits-service"
  ["vets-service"]="spring-petclinic-vets-service"
  ["genai-service"]="spring-petclinic-genai-service"
  ["admin-server"]="spring-petclinic-admin-server"
)

declare -A SERVICE_PORT=(
  ["config-server"]="8888"
  ["discovery-server"]="8761"
  ["api-gateway"]="8080"
  ["customers-service"]="8081"
  ["visits-service"]="8082"
  ["vets-service"]="8083"
  ["genai-service"]="8084"
  ["admin-server"]="9090"
)

ALL_SERVICES="config-server discovery-server api-gateway customers-service visits-service vets-service genai-service admin-server"

# ── Argument parsing ──────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)        ENV="$2";      shift 2 ;;
    --tag)        TAG="$2";      shift 2 ;;
    --app-dir)    APP_DIR="$2";  shift 2 ;;
    --region)     REGION="$2";   shift 2 ;;
    --services)   SERVICES="$2"; shift 2 ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 --env <dev|prod> [--tag TAG] [--app-dir PATH] [--region REGION] [--services 'svc1 svc2']" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${ENV}" ]]; then
  echo "Error: --env is required (dev or prod)" >&2
  exit 1
fi

if [[ ! -d "${APP_DIR}" ]]; then
  echo "Error: app directory not found: ${APP_DIR}" >&2
  echo "Pass --app-dir to specify the spring-petclinic-microservices path." >&2
  exit 1
fi

# ── Derived values ────────────────────────────────────────────────────────────

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
DOCKERFILE="${APP_DIR}/docker/Dockerfile"

if [[ -z "${TAG}" ]]; then
  TAG=$(cd "${APP_DIR}" && git rev-parse --short=7 HEAD 2>/dev/null || echo "v1.0.0")
fi

BUILD_SERVICES="${SERVICES:-${ALL_SERVICES}}"

echo "============================================================"
echo "ECR build-push"
echo "  env:      ${ENV}"
echo "  tag:      ${TAG}"
echo "  registry: ${REGISTRY}"
echo "  app dir:  ${APP_DIR}"
echo "  services: ${BUILD_SERVICES}"
echo "============================================================"

# ── ECR login ─────────────────────────────────────────────────────────────────

echo ""
echo ">>> Authenticating to ECR..."
aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}"

# ── Ensure buildx builder with QEMU (ARM64 cross-compilation) ─────────────────

echo ""
echo ">>> Setting up docker buildx for linux/arm64..."
if ! docker buildx inspect petclinic-arm64 &>/dev/null; then
  docker buildx create --name petclinic-arm64 --driver docker-container --bootstrap
fi
docker buildx use petclinic-arm64

# ── Maven build ───────────────────────────────────────────────────────────────

echo ""
echo ">>> Building JARs with Maven (skipping tests)..."
cd "${APP_DIR}"
./mvnw clean install -DskipTests --no-transfer-progress

# ── Build and push each service ───────────────────────────────────────────────

PUSH_FAILED=()

for SERVICE in ${BUILD_SERVICES}; do
  MODULE="${SERVICE_MODULE[${SERVICE}]:-}"
  PORT="${SERVICE_PORT[${SERVICE}]:-}"

  if [[ -z "${MODULE}" ]]; then
    echo ""
    echo "WARNING: Unknown service '${SERVICE}', skipping." >&2
    continue
  fi

  echo ""
  echo ">>> Building ${SERVICE} (port ${PORT}) ..."

  # Find the JAR — Maven puts it in target/ as {module}-{version}.jar
  JAR_PATH=$(find "${APP_DIR}/${MODULE}/target" -maxdepth 1 -name "${MODULE}-*.jar" \
    ! -name "*-sources.jar" ! -name "*-tests.jar" | head -1)

  if [[ -z "${JAR_PATH}" ]]; then
    echo "ERROR: JAR not found in ${APP_DIR}/${MODULE}/target — did Maven build succeed?" >&2
    PUSH_FAILED+=("${SERVICE}")
    continue
  fi

  JAR_FILENAME="$(basename "${JAR_PATH}")"
  ARTIFACT_NAME="${JAR_FILENAME%.jar}"
  ECR_IMAGE="${REGISTRY}/petclinic-${ENV}/${SERVICE}:${TAG}"

  # Copy JAR into docker/ so the Dockerfile COPY can reach it
  cp "${JAR_PATH}" "${APP_DIR}/docker/${JAR_FILENAME}"

  docker buildx build \
    --platform linux/arm64 \
    --build-arg "ARTIFACT_NAME=${ARTIFACT_NAME}" \
    --build-arg "EXPOSED_PORT=${PORT}" \
    --tag "${ECR_IMAGE}" \
    --file "${DOCKERFILE}" \
    --push \
    "${APP_DIR}/docker/"

  # Clean up the copied JAR
  rm -f "${APP_DIR}/docker/${JAR_FILENAME}"

  echo "    Pushed: ${ECR_IMAGE}"
done

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "============================================================"
if [[ ${#PUSH_FAILED[@]} -eq 0 ]]; then
  echo "All images pushed successfully."
  echo ""
  echo "Images in ECR (petclinic-${ENV}):"
  for SERVICE in ${BUILD_SERVICES}; do
    echo "  ${REGISTRY}/petclinic-${ENV}/${SERVICE}:${TAG}"
  done
else
  echo "WARNING: The following services failed: ${PUSH_FAILED[*]}"
  exit 1
fi
echo "============================================================"
