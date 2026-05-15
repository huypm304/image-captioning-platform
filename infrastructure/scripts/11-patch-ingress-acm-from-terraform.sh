#!/usr/bin/env bash
# Patch ACM ARN on ALB Ingresses from Terraform state (preferred) or AWS ACM lookup (fallback).
# Run from repo root with: AWS creds, kubectl context = EKS.
# If infrastructure/terraform/backend.hcl is missing (e.g. Jenkins workspace), it is generated
# from the current AWS account — same bucket/key pattern as ci/jenkins/stages/build_sw/update-gitops.yaml.
#
# Optional env:
#   ACM_CERTIFICATE_ARN  If set, skip discovery and use this ARN.
#   ACM_LOOKUP_DOMAIN    For AWS fallback (default: minhhuy.me), must match Terraform var.domain_name.
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
DOMAIN="${ACM_LOOKUP_DOMAIN:-minhhuy.me}"

write_backend_hcl() {
  local account
  account="$(aws sts get-caller-identity --query Account --output text)"
  printf 'bucket = "image-caption-dev-tfstate-%s"\nkey = "image-caption/dev/terraform.tfstate"\nregion = "%s"\ndynamodb_table = "image-caption-dev-tflock"\nencrypt = true\n' \
    "${account}" "${REGION}" >"${TF_DIR}/backend.hcl"
  echo "Wrote ${TF_DIR}/backend.hcl for account ${account} (gitignored; same layout as CI)." >&2
}

resolve_cert_arn() {
  if [[ -n "${ACM_CERTIFICATE_ARN:-}" ]]; then
    echo "${ACM_CERTIFICATE_ARN}"
    return 0
  fi

  if [[ ! -f "${TF_DIR}/backend.hcl" ]]; then
    echo "No ${TF_DIR}/backend.hcl — generating from current AWS account..." >&2
    write_backend_hcl
  fi

  local out=""
  cd "${TF_DIR}"
  if terraform init -input=false -no-color -backend-config=backend.hcl >/dev/null 2>&1; then
    out="$(terraform output -raw acm_certificate_arn 2>/dev/null || true)"
  else
    echo "WARN: terraform init failed (missing state bucket or terraform not installed); trying ACM API." >&2
  fi
  if [[ -n "${out}" && "${out}" != "null" ]]; then
    echo "${out}"
    return 0
  fi

  echo "Terraform output unavailable; listing ISSUED ACM certs for ${DOMAIN} in ${REGION}..." >&2
  aws acm list-certificates --region "${REGION}" --certificate-statuses ISSUED \
    --query "CertificateSummaryList[?DomainName=='${DOMAIN}' || DomainName=='*.${DOMAIN}'].CertificateArn | [0]" \
    --output text
}

CERT_ARN="$(resolve_cert_arn)"
CERT_ARN="$(echo -n "${CERT_ARN}" | tr -d '[:space:]')"
if [[ -z "${CERT_ARN}" || "${CERT_ARN}" == "None" || "${CERT_ARN}" == "null" ]]; then
  echo "ERROR: Could not resolve ACM certificate ARN. Set ACM_CERTIFICATE_ARN, fix Terraform remote state, or ensure an ISSUED cert exists for ${DOMAIN}."
  exit 1
fi
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
    echo "Patching ${ns}/${name} (HTTP+HTTPS + ACM + redirect) ..."
    kubectl annotate ingress "${name}" -n "${ns}" \
      "alb.ingress.kubernetes.io/certificate-arn=${CERT_ARN}" \
      'alb.ingress.kubernetes.io/listen-ports=[{"HTTP":80},{"HTTPS":443}]' \
      'alb.ingress.kubernetes.io/ssl-redirect=443' \
      --overwrite
  else
    echo "(skip) Ingress ${ns}/${name} not found yet — apply Argo apps / sync first."
  fi
}

patch_ingress argocd argocd-server-ingress
patch_ingress monitoring grafana-ingress

echo "Done. Watch: kubectl describe ingress -n argocd argocd-server-ingress | tail -20"
echo "Verify ALB annotations (do not parse raw JSON with tr/sed on commas):"
echo "  kubectl get ingress -n argocd argocd-server-ingress -o jsonpath='{.metadata.annotations.alb\\.ingress\\.kubernetes\\.io/listen-ports}{\"\\n\"}'"
echo "Probe UI (follow redirects): curl -skL -o /dev/null -w '%{http_code}\\n' -H 'Host: argocd.minhhuy.me' 'https://<ALB_DNS>/'"
echo "DNS: argocd.minhhuy.me must resolve to the same ALB as app (CNAME/A to ALB DNS from kubectl get ingress -A)."
