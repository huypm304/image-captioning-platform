#!/usr/bin/env bash
# Replace __*__ placeholders in GitOps files (same logic as ci/jenkins/stages/build_sw/update-gitops.yaml)
# without pushing. Use when Argo CD synced the repo but Jenkins has not yet committed real ECR/Terraform values.
#
# Requirements: repo root, AWS creds, terraform backend (see 11-patch-ingress-acm-from-terraform.sh).
# Env:
#   IMAGE_TAG        Required — ECR image tag that exists for both BE and FE (e.g. Jenkins BUILD_NUMBER).
#   ECR_REGISTRY     Optional — default: <account>.dkr.ecr.<region>.amazonaws.com
#   ECR_REPO_BE      Optional — default: image-caption-dev-app
#   ECR_REPO_FE      Optional — default: image-caption-dev-frontend
#
# After run: git diff, commit, push to the branch Argo tracks (e.g. feature/test), then Refresh in Argo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-southeast-1}}"
export AWS_DEFAULT_REGION="${REGION}"

if [[ -z "${IMAGE_TAG:-}" ]]; then
  echo "ERROR: set IMAGE_TAG to an existing ECR tag (e.g. export IMAGE_TAG=15)" >&2
  exit 1
fi

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
ECR_REGISTRY="${ECR_REGISTRY:-${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com}"
ECR_REPO_BE="${ECR_REPO_BE:-image-caption-dev-app}"
ECR_REPO_FE="${ECR_REPO_FE:-image-caption-dev-frontend}"
BE_REPO="${ECR_REGISTRY}/${ECR_REPO_BE}"
FE_REPO="${ECR_REGISTRY}/${ECR_REPO_FE}"

TF_DIR="${ROOT}/infrastructure/terraform"
if [[ ! -f "${TF_DIR}/backend.hcl" ]]; then
  printf 'bucket = "image-caption-dev-tfstate-%s"\nkey = "image-caption/dev/terraform.tfstate"\nregion = "%s"\ndynamodb_table = "image-caption-dev-tflock"\nencrypt = true\n' \
    "${ACCOUNT}" "${REGION}" >"${TF_DIR}/backend.hcl"
  echo "Wrote ${TF_DIR}/backend.hcl" >&2
fi
cd "${TF_DIR}"
terraform init -input=false -no-color -backend-config=backend.hcl >/dev/null
BUCKET="$(terraform output -raw models_bucket)"
ROLE_ARN="$(terraform output -raw demo_app_role_arn)"
CERT_ARN="$(terraform output -raw acm_certificate_arn)"
cd "${ROOT}"

echo "Using IMAGE_TAG=${IMAGE_TAG}  BE=${BE_REPO}  FE=${FE_REPO}" >&2

sed -i.bak \
  -e "s|__BACKEND_IMAGE_REPO__|${BE_REPO}|g" \
  -e "s|__FRONTEND_IMAGE_REPO__|${FE_REPO}|g" \
  -e "s|__IMAGE_TAG__|${IMAGE_TAG}|g" \
  -e "s|__DEMO_APP_ROLE_ARN__|${ROLE_ARN}|g" \
  -e "s|__MODELS_BUCKET__|${BUCKET}|g" \
  -e "s|__ACM_CERTIFICATE_ARN__|${CERT_ARN}|g" \
  "${ROOT}/deploy/helm/demo-app/values-argocd.yaml"
rm -f "${ROOT}/deploy/helm/demo-app/values-argocd.yaml.bak"

sed -i.bak \
  -e "s|__ACM_CERTIFICATE_ARN__|${CERT_ARN}|g" \
  -e "s#alb.ingress.kubernetes.io/certificate-arn:.*#alb.ingress.kubernetes.io/certificate-arn: ${CERT_ARN}#" \
  "${ROOT}/deploy/argocd/manifests/grafana/ingress.yaml" \
  "${ROOT}/deploy/argocd/manifests/argocd-ingress/ingress.yaml"
rm -f "${ROOT}/deploy/argocd/manifests/grafana/ingress.yaml.bak" "${ROOT}/deploy/argocd/manifests/argocd-ingress/ingress.yaml.bak"

echo "Done. Review: git diff deploy/helm/demo-app/values-argocd.yaml deploy/argocd/manifests/grafana/ingress.yaml deploy/argocd/manifests/argocd-ingress/ingress.yaml"
echo "Then: git add deploy/helm/demo-app/values-argocd.yaml deploy/argocd/manifests/grafana/ingress.yaml deploy/argocd/manifests/argocd-ingress/ingress.yaml && git commit && git push origin <branch>  &&  Argo CD Refresh (applications argocd-ingress, grafana-ingress, image-captioning)"
