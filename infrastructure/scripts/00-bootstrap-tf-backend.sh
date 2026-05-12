#!/usr/bin/env bash
# Run once (with AWS credentials) to create S3 + DynamoDB for Terraform remote state.
# Then run from repo root: see README for terraform init -migrate-state if you had local state.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-southeast-1}}"
export AWS_DEFAULT_REGION="${REGION}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="image-caption-dev-tfstate-${ACCOUNT_ID}"
TABLE="image-caption-dev-tflock"

echo "=== Bootstrap Terraform remote backend ==="
echo "Region:      ${REGION}"
echo "Account:     ${ACCOUNT_ID}"
echo "S3 bucket:   ${BUCKET}"
echo "DynamoDB:    ${TABLE}"
echo ""

# S3 bucket
if aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  echo "Bucket ${BUCKET} already exists."
else
  echo "Creating bucket ${BUCKET}..."
  aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}" \
    --create-bucket-configuration "LocationConstraint=${REGION}"
fi

aws s3api put-bucket-versioning --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "${BUCKET}" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket "${BUCKET}" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# DynamoDB lock table
if aws dynamodb describe-table --table-name "${TABLE}" --region "${REGION}" >/dev/null 2>&1; then
  echo "DynamoDB table ${TABLE} already exists."
else
  echo "Creating DynamoDB table ${TABLE}..."
  aws dynamodb create-table --table-name "${TABLE}" --region "${REGION}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST
  echo "Waiting for table to become ACTIVE..."
  aws dynamodb wait table-exists --table-name "${TABLE}" --region "${REGION}"
fi

# Write backend.hcl for local terraform init (gitignored)
cat > "${TF_DIR}/backend.hcl" <<EOF
bucket         = "${BUCKET}"
key            = "image-caption/dev/terraform.tfstate"
region         = "${REGION}"
dynamodb_table = "${TABLE}"
encrypt        = true
EOF

echo ""
echo "=== Backend ready ==="
echo "Wrote ${TF_DIR}/backend.hcl"
echo ""
echo "Next (local, first time with existing local state):"
echo "  cd infrastructure/terraform && terraform init -migrate-state -backend-config=backend.hcl"
echo ""
echo "Next (Jenkins): create job with Script Path ci/jenkins/Jenkinsfile.infra; default STAGE=plan."
