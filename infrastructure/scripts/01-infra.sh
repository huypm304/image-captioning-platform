#!/usr/bin/env bash
# Recommended: use Jenkins infra pipeline (remote S3 state + plan artifacts).
#   Job Script Path: ci/jenkins/Jenkinsfile.infra — default STAGE=plan; apply manually.
# This script is for local development only (after infrastructure/scripts/00-bootstrap-tf-backend.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"

echo "=== Phase 1: Terraform Infrastructure (local) ==="

cd "$TF_DIR"

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-southeast-1}}"
export AWS_DEFAULT_REGION="${REGION}"

if [ ! -f backend.hcl ]; then
  echo "Generating backend.hcl from current AWS account (bucket must exist — run infrastructure/scripts/00-bootstrap-tf-backend.sh first)..."
  ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
  printf '%s\n' \
    "bucket         = \"image-caption-dev-tfstate-${ACCOUNT}\"" \
    'key            = "image-caption/dev/terraform.tfstate"' \
    "region         = \"${REGION}\"" \
    'dynamodb_table = "image-caption-dev-tflock"' \
    'encrypt        = true' \
    > backend.hcl
fi

echo "[1/3] terraform init"
terraform init -input=false -backend-config=backend.hcl

echo "[2/3] terraform plan"
terraform plan -out=tfplan

echo "[3/3] terraform apply"
terraform apply tfplan

echo "=== Infrastructure provisioned ==="
terraform output
