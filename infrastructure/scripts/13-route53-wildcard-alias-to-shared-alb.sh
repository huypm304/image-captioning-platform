#!/usr/bin/env bash
# Upsert Route53 wildcard A (ALIAS) -> shared ALB from Ingress (group image-caption).
# Run after ALB has an ADDRESS (e.g. end of app CI or bootstrap). Requires: AWS creds with route53:ChangeResourceRecordSets,
# kubectl to EKS, terraform state (backend.hcl).
#
# Optional env:
#   WAIT_ALB_MAX_SEC   Max wait for Ingress ADDRESS (default 600).
#   INGRESS_NS / INGRESS_NAME   Primary ingress to read ALB host (defaults: default image-captioning-ingress).
#   SKIP_ROUTE53_WILDCARD   If set to 1, only Argo refresh (no DNS).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-southeast-1}}"
export AWS_DEFAULT_REGION="${REGION}"
WAIT_ALB_MAX_SEC="${WAIT_ALB_MAX_SEC:-600}"
INGRESS_NS="${INGRESS_NS:-default}"
INGRESS_NAME="${INGRESS_NAME:-image-captioning-ingress}"

TF_DIR="${ROOT}/infrastructure/terraform"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
if [[ ! -f "${TF_DIR}/backend.hcl" ]]; then
  printf 'bucket = "image-caption-dev-tfstate-%s"\nkey = "image-caption/dev/terraform.tfstate"\nregion = "%s"\ndynamodb_table = "image-caption-dev-tflock"\nencrypt = true\n' \
    "${ACCOUNT}" "${REGION}" >"${TF_DIR}/backend.hcl"
fi
cd "${TF_DIR}"
terraform init -input=false -no-color -backend-config=backend.hcl >/dev/null
ZONE_ID=$(terraform output -raw route53_zone_id)
DOMAIN=$(terraform output -raw domain_name)
cd "${ROOT}"

argocd_hard_refresh() {
  if ! command -v kubectl &>/dev/null; then
    echo "WARN: kubectl not found; skip Argo CD hard refresh."
    return 0
  fi
  if ! kubectl cluster-info &>/dev/null; then
    echo "WARN: kubectl cannot reach API; skip Argo CD hard refresh."
    return 0
  fi
  if kubectl get application image-captioning -n argocd &>/dev/null; then
    kubectl patch application image-captioning -n argocd --type merge \
      -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' 2>/dev/null || true
    echo "Requested Argo CD hard refresh for application image-captioning."
  else
    echo "WARN: Application image-captioning not in cluster; skip Argo CD hard refresh."
  fi
}

if [[ "${SKIP_ROUTE53_WILDCARD:-0}" == "1" ]]; then
  echo "SKIP_ROUTE53_WILDCARD=1: skipping DNS; still running Argo refresh."
  argocd_hard_refresh
  exit 0
fi

if ! command -v kubectl &>/dev/null || ! kubectl cluster-info &>/dev/null; then
  echo "WARN: kubectl missing or cluster unreachable; skip Route53 wildcard (run again with kubeconfig)."
  argocd_hard_refresh
  exit 0
fi

deadline=$((SECONDS + WAIT_ALB_MAX_SEC))
ALB_HOST=""
while true; do
  ALB_HOST=$(kubectl get ingress "${INGRESS_NAME}" -n "${INGRESS_NS}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [[ -n "${ALB_HOST}" ]]; then
    break
  fi
  # Fallback: Argo CD ingress same ALB group
  ALB_HOST=$(kubectl get ingress argocd-server-ingress -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [[ -n "${ALB_HOST}" ]]; then
    break
  fi
  if (( SECONDS >= deadline )); then
    echo "WARN: No Ingress ADDRESS after ${WAIT_ALB_MAX_SEC}s; skip Route53 wildcard. Re-run pipeline when ALB is ready."
    argocd_hard_refresh
    exit 0
  fi
  echo "Waiting for ALB hostname on Ingress (${INGRESS_NS}/${INGRESS_NAME} or argocd/argocd-server-ingress) ..."
  sleep 15
done

echo "Using ALB DNS: ${ALB_HOST}"

# Resolve ELB canonical hosted zone ID (Route53 alias target; paginated describe covers many LBs in account)
LB_QUERY="${ALB_HOST#dualstack.}"
CANONICAL_ZID=""
if command -v jq &>/dev/null; then
  CANONICAL_ZID=$(aws elbv2 describe-load-balancers --region "${REGION}" --output json 2>/dev/null \
    | jq -r --arg h "${ALB_HOST}" --arg q "${LB_QUERY}" \
      '.LoadBalancers[] | select(.DNSName == $h or .DNSName == $q or .DNSName == ("dualstack."+$q)) | .CanonicalHostedZoneId' \
    | head -1)
else
  CANONICAL_ZID=$(aws elbv2 describe-load-balancers --region "${REGION}" \
    --query "LoadBalancers[?DNSName=='${LB_QUERY}' || DNSName=='${ALB_HOST}' || DNSName=='dualstack.${LB_QUERY}'].CanonicalHostedZoneId | [0]" --output text 2>/dev/null || true)
fi
if [[ -z "${CANONICAL_ZID}" || "${CANONICAL_ZID}" == "None" ]]; then
  echo "ERROR: Could not resolve CanonicalHostedZoneId for ${ALB_HOST} (wrong region or not an ALB?)."
  argocd_hard_refresh
  exit 1
fi

WILDCARD_FQDN="*.${DOMAIN}."
ALB_DNS_TARGET="${ALB_HOST}."
if [[ "${ALB_HOST}" != dualstack.* ]] && command -v jq &>/dev/null; then
  DS_DNS=$(aws elbv2 describe-load-balancers --region "${REGION}" --output json 2>/dev/null \
    | jq -r --arg q "${LB_QUERY}" '.LoadBalancers[] | select(.DNSName == ("dualstack."+$q)) | .DNSName' | head -1)
  if [[ -n "${DS_DNS}" ]]; then
    ALB_DNS_TARGET="${DS_DNS}."
  fi
fi

TMP_JSON=$(mktemp)
trap 'rm -f "${TMP_JSON}"' EXIT
cat >"${TMP_JSON}" <<EOF
{
  "Comment": "Upsert wildcard to shared ALB (${ALB_HOST})",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${WILDCARD_FQDN}",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "${CANONICAL_ZID}",
          "DNSName": "${ALB_DNS_TARGET}",
          "EvaluateTargetHealth": true
        }
      }
    }
  ]
}
EOF

echo "Upserting Route53 ${WILDCARD_FQDN} ALIAS -> ${ALB_DNS_TARGET} (zone ${ZONE_ID}) ..."
aws route53 change-resource-record-sets --hosted-zone-id "${ZONE_ID}" --change-batch "file://${TMP_JSON}"
echo "Route53 wildcard updated."

argocd_hard_refresh
