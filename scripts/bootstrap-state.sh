#!/usr/bin/env bash
# scripts/bootstrap-state.sh
#
# Provisions the S3 bucket and DynamoDB table used for Terraform remote state.
# Run once before `terraform init`. Safe to run multiple times (idempotent).
#
# Usage:
#   ./scripts/bootstrap-state.sh [--region eu-central-1]
#
# After running this script, run:
#   cd terraform/environments/dev  && terraform init
#   cd terraform/environments/prod && terraform init

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
REGION="eu-central-1"
PROJECT="petclinic"

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      REGION="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '2,13p' "$0" | sed 's/^# //'
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# ── Verify AWS credentials ────────────────────────────────────────────────────
echo "Verifying AWS credentials..."
if ! ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null); then
  echo "ERROR: AWS credentials not configured or not valid." >&2
  echo "Run: aws configure  (or set AWS_PROFILE / AWS_ACCESS_KEY_ID)" >&2
  exit 1
fi
echo "AWS Account ID : $ACCOUNT_ID"
echo "Region         : $REGION"

BUCKET_NAME="${PROJECT}-terraform-state-${ACCOUNT_ID}"
TABLE_NAME="${PROJECT}-terraform-locks"

echo ""
echo "── S3 State Bucket ──────────────────────────────────────────────────────"

# Check if bucket exists (returns exit 0 if exists, non-zero if not)
BUCKET_EXISTS=false
if aws s3api head-bucket --bucket "$BUCKET_NAME" --output text 2>/dev/null; then
  BUCKET_EXISTS=true
fi

if [[ "$BUCKET_EXISTS" == "false" ]]; then
  echo "Creating bucket: $BUCKET_NAME"
  if [[ "$REGION" == "us-east-1" ]]; then
    aws s3api create-bucket \
      --bucket "$BUCKET_NAME" \
      --region "$REGION" \
      --output text > /dev/null
  else
    aws s3api create-bucket \
      --bucket "$BUCKET_NAME" \
      --region "$REGION" \
      --create-bucket-configuration "LocationConstraint=$REGION" \
      --output text > /dev/null
  fi
  echo "Bucket created : $BUCKET_NAME"
else
  echo "Bucket exists  : $BUCKET_NAME (skipping creation)"
fi

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled \
  --output text > /dev/null
echo "Versioning     : enabled"

# Enable server-side encryption (AES256 / SSE-S3) — write JSON to a temp file
# to avoid shell quoting issues on Windows
ENCRYPTION_CONFIG_FILE="$(mktemp)"
cat > "$ENCRYPTION_CONFIG_FILE" <<'EOF'
{
  "Rules": [{
    "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"},
    "BucketKeyEnabled": true
  }]
}
EOF
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration "file://$ENCRYPTION_CONFIG_FILE" \
  --output text > /dev/null
rm -f "$ENCRYPTION_CONFIG_FILE"
echo "Encryption     : AES256 (SSE-S3)"

# Block all public access — write JSON to a temp file
PUBLIC_ACCESS_FILE="$(mktemp)"
cat > "$PUBLIC_ACCESS_FILE" <<'EOF'
{
  "BlockPublicAcls": true,
  "IgnorePublicAcls": true,
  "BlockPublicPolicy": true,
  "RestrictPublicBuckets": true
}
EOF
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration "file://$PUBLIC_ACCESS_FILE" \
  --output text > /dev/null
rm -f "$PUBLIC_ACCESS_FILE"
echo "Public access  : blocked (all 4 settings)"

echo ""
echo "── DynamoDB Lock Table ──────────────────────────────────────────────────"

TABLE_EXISTS=false
if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" --output text > /dev/null 2>&1; then
  TABLE_EXISTS=true
fi

if [[ "$TABLE_EXISTS" == "false" ]]; then
  echo "Creating table : $TABLE_NAME"
  aws dynamodb create-table \
    --table-name "$TABLE_NAME" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION" \
    --output text > /dev/null

  echo "Waiting for table to become active..."
  aws dynamodb wait table-exists --table-name "$TABLE_NAME" --region "$REGION"
  echo "Table created  : $TABLE_NAME"
else
  echo "Table exists   : $TABLE_NAME (skipping creation)"
fi
echo "Partition key  : LockID (String)"
echo "Billing mode   : PAY_PER_REQUEST"

echo ""
echo "── Updating backend.tf files ────────────────────────────────────────────"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

for env in dev prod; do
  BACKEND_FILE="$REPO_ROOT/terraform/environments/$env/backend.tf"
  if [[ -f "$BACKEND_FILE" ]]; then
    if grep -q "ACCOUNT_ID" "$BACKEND_FILE"; then
      if [[ "$(uname -s)" == "Darwin" ]]; then
        sed -i '' "s/ACCOUNT_ID/${ACCOUNT_ID}/g" "$BACKEND_FILE"
      else
        sed -i "s/ACCOUNT_ID/${ACCOUNT_ID}/g" "$BACKEND_FILE"
      fi
      echo "Updated        : terraform/environments/$env/backend.tf"
    else
      echo "Already set    : terraform/environments/$env/backend.tf"
    fi
  else
    echo "WARNING: $BACKEND_FILE not found — skipping." >&2
  fi
done

echo ""
echo "═══════════════════════════════════════════════════════════════════════"
echo "Bootstrap complete!"
echo ""
echo "S3 bucket   : $BUCKET_NAME"
echo "DynamoDB    : $TABLE_NAME (region: $REGION)"
echo ""
echo "Next steps:"
echo "  cd terraform/environments/dev  && terraform init"
echo "  cd terraform/environments/prod && terraform init"
echo "═══════════════════════════════════════════════════════════════════════"
