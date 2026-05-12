#!/usr/bin/env bash
# One-time: install Argo CD into the EKS cluster (namespace argocd).
set -euo pipefail

CLUSTER_NAME="${1:-image-caption-dev-eks}"
REGION="${2:-ap-southeast-1}"

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
  echo "     (or: ./scripts/02-configure-kubectl.sh)"
  echo "  3) kubectl get nodes   # must work before Helm"
  exit 1
fi

helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set server.service.type=ClusterIP \
  --wait --timeout 10m

echo ""
echo "Argo CD installed. Get initial admin password:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"
echo ""
echo "Port-forward UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
echo "Then register Applications:"
echo "  kubectl apply -f gitops/applications/"
echo "(Edit repoURL in those YAML files if this repo is forked.)"
