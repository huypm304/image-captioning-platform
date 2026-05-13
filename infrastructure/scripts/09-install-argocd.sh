#!/usr/bin/env bash
# One-time: install Argo CD into the EKS cluster (namespace argocd).
set -euo pipefail

CLUSTER_NAME="${1:-image-caption-dev-eks}"
REGION="${2:-ap-southeast-1}"
# Public URL behind ALB (TLS at load balancer). Override if you use another hostname.
ARGOCD_PUBLIC_URL="${ARGOCD_PUBLIC_URL:-https://argocd.minhhuy.me}"

echo "=== Installing Argo CD (Helm) ==="
echo "Cluster: ${CLUSTER_NAME}  Region: ${REGION}"

if ! command -v kubectl &>/dev/null; then
  echo "ERROR: kubectl not found. Install kubectl first."
  exit 1
fi
if ! kubectl cluster-info &>/dev/null; then
  echo "ERROR: Cannot reach the Kubernetes API (cluster deleted, wrong context, or no network)."
  echo "Fix order:"
  echo "  1) terraform apply (or Jenkins Infra job) so EKS exists"
  echo "  2) aws eks update-kubeconfig --region ${REGION} --name ${CLUSTER_NAME}"
  echo "     (or: ./infrastructure/scripts/02-configure-kubectl.sh)"
  echo "  3) kubectl get nodes   # must work before Helm"
  exit 1
fi

helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo

# TLS terminates at ALB; pods see HTTP. Must set insecure or Argo 307-redirects to HTTPS forever (browser -310).
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set server.service.type=ClusterIP \
  --set server.insecure=true \
  --wait --timeout 10m

# Cmd params CM is what argocd-server reads; keep in sync with ALB + public URL.
if kubectl get configmap argocd-cmd-params-cm -n argocd &>/dev/null; then
  kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge \
    -p "{\"data\":{\"server.url\":\"${ARGOCD_PUBLIC_URL}\",\"server.insecure\":\"true\"}}"
  kubectl rollout restart deployment argocd-server -n argocd
  kubectl rollout status deployment argocd-server -n argocd --timeout=5m
fi

echo ""
echo "Argo CD installed."
echo "  UI (HTTPS on ALB after ingress + ./infrastructure/scripts/11-patch-ingress-acm-from-terraform.sh): ${ARGOCD_PUBLIC_URL}"
echo "  Fallback: kubectl port-forward svc/argocd-server -n argocd 8080:80  then http://localhost:8080"
echo ""
echo "Initial admin password:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"
echo ""
echo "Helm uses server.insecure=true; argocd-cmd-params-cm sets server.insecure + server.url so ALB→HTTP does not trigger HTTPS redirect loops (-310)."
echo ""
echo "Register Applications (edit repoURL if forked):"
echo "  kubectl apply -f deploy/argocd/applications/"
echo ""
echo "If UI shows redirect loop (-310 / ERR_TOO_MANY_REDIRECTS), patch cmd-params and restart:"
echo "  kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p \"{\\\"data\\\":{\\\"server.insecure\\\":\\\"true\\\",\\\"server.url\\\":\\\"${ARGOCD_PUBLIC_URL}\\\"}}\""
echo "  kubectl rollout restart deployment argocd-server -n argocd"
