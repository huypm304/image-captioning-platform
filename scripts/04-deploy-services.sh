#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."
HELM_DIR="${PROJECT_DIR}/helm"
K8S_DIR="${PROJECT_DIR}/k8s"

echo "=== Phase 3: Deploy Services via Helm ==="

# Create namespaces
echo "[1/4] Creating namespaces"
kubectl apply -f "${K8S_DIR}/namespaces.yaml"

# Add Helm repos
echo "[2/4] Adding Helm repositories"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Monitoring (Prometheus + Grafana)
echo "[3/4] Installing kube-prometheus-stack"
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f "${HELM_DIR}/monitoring-values.yaml" \
  --wait --timeout 5m

# Logging: Promtail → Loki; Grafana uses this via monitoring-values additionalDataSources
echo "[4/4] Installing Loki stack"
helm upgrade --install loki grafana/loki-stack \
  -n logging \
  -f "${HELM_DIR}/loki-values.yaml" \
  --wait --timeout 5m

echo ""
echo "=== All services deployed ==="
echo ""
echo "Grafana:    kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring"
echo "Demo app:   Jenkins (jenkins/Jenkinsfile) → ECR + GitOps; ./scripts/08-upload-models.sh syncs backend/patched_models/ to S3"
