#!/usr/bin/env bash
# Sync local patched_models/ to the Terraform-created S3 bucket (requires AWS credentials).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-southeast-1}}"
export AWS_DEFAULT_REGION="${REGION}"

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
BUCKET="image-caption-dev-models-${ACCOUNT}"
LOCAL_DIR="${SCRIPT_DIR}/../image-captioning/patched_models"

if [ ! -d "${LOCAL_DIR}" ]; then
  echo "Missing ${LOCAL_DIR} — add model files locally before sync."
  exit 1
fi

echo "Syncing ${LOCAL_DIR} -> s3://${BUCKET}/patched_models/"
aws s3 sync "${LOCAL_DIR}" "s3://${BUCKET}/patched_models/" --region "${REGION}"
echo "Done."
