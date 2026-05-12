#!/usr/bin/env bash
# Patch ACM ARN on ALB Ingresses from Terraform state (when Jenkins gitops has not run yet).
# Run from repo root with: AWS creds, kubectl context = EKS, terraform backend already configured.
#
# Usage:
#   ./infrastructure/scripts/11-patch-ingress-acm-from-terraform.sh
#   ./infrastructure/scripts/11-patch-ingress-acm-from-terraform.sh --wait
#     --wait  polls until argocd-server-ingress exists (required), optionally grafana-ingress (best-effort),
#             then patches. Used by bootstrap install-argocd.
set -euo pipefail

WAIT_MODE=0
for arg in "$@"; do
  [[ "${arg}" == "--wait" ]] && WAIT_MODE=1
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WAIT_INGRESS_MAX="${WAIT_INGRESS_MAX:-600}"
GRAFANA_WAIT_EXTRA="${GRAFANA_WAIT_EXTRA:-180}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-southeast-1}}"
export AWS_DEFAULT_REGION="${REGION}"

TF_DIR="${ROOT}/infrastructure/terraform"
if [[ ! -f "${TF_DIR}/backend.hcl" ]]; then
  echo "Missing ${TF_DIR}/backend.hcl — run 00-bootstrap-tf-backend.sh or copy from Terraform output."
  exit 1
fi

cd "${TF_DIR}"
terraform init -input=false -no-color -backend-config=backend.hcl >/dev/null
CERT_ARN=$(terraform output -raw acm_certificate_arn)
echo "Using ACM: ${CERT_ARN}"

if [[ "${WAIT_MODE}" -eq 1 ]]; then
  deadline=$((SECONDS + WAIT_INGRESS_MAX))
  echo "Waiting for Ingress argocd/argocd-server-ingress (max ${WAIT_INGRESS_MAX}s) ..."
  while ! kubectl get ingress argocd-server-ingress -n argocd &>/dev/null; do
    if (( SECONDS >= deadline )); then
      echo "ERROR: argocd-server-ingress not found in time. Sync Argo apps or check ALB controller."
      exit 1
    fi
    sleep 10
  done
  g_end=$((SECONDS + GRAFANA_WAIT_EXTRA))
  echo "Waiting for Ingress monitoring/grafana-ingress (best-effort, max ${GRAFANA_WAIT_EXTRA}s) ..."
  while ! kubectl get ingress grafana-ingress -n monitoring &>/dev/null; do
    if (( SECONDS >= g_end )); then
      echo "(warn) grafana-ingress not ready yet; patch will skip it if still missing."
      break
    fi
    sleep 10
  done
fi

patch_ingress() {
  local ns="$1" name="$2"
  if kubectl get ingress "${name}" -n "${ns}" &>/dev/null; then
    echo "Patching ${ns}/${name} ..."
    kubectl annotate ingress "${name}" -n "${ns}" \
      "alb.ingress.kubernetes.io/certificate-arn=${CERT_ARN}" \
      --overwrite
  else
    echo "(skip) Ingress ${ns}/${name} not found yet — apply Argo apps / sync first."
  fi
}

patch_ingress argocd argocd-server-ingress
patch_ingress monitoring grafana-ingress

echo "Done. Watch: kubectl describe ingress -n argocd argocd-server-ingress | tail -20"
echo "DNS: argocd.minhhuy.me must resolve to the same ALB as app (CNAME/A to ALB DNS from kubectl get ingress -A)."
