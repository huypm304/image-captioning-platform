#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."
HELM_DIR="${PROJECT_DIR}/helm"
K8S_DIR="${PROJECT_DIR}/k8s"

echo "=== Phase 3: Deploy Services via Helm ==="

# Create namespaces
echo "[1/5] Creating namespaces"
kubectl apply -f "${K8S_DIR}/namespaces.yaml"

# Add Helm repos
echo "[2/5] Adding Helm repositories"
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# PostgreSQL
echo "[3/5] Installing PostgreSQL"
helm upgrade --install postgres bitnami/postgresql \
  -n database \
  -f "${HELM_DIR}/postgres-values.yaml" \
  --wait --timeout 5m

# Monitoring (Prometheus + Grafana)
echo "[4/5] Installing kube-prometheus-stack"
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f "${HELM_DIR}/monitoring-values.yaml" \
  --wait --timeout 5m

# Logging (Loki + Promtail)
echo "[5/5] Installing Loki stack"
helm upgrade --install loki grafana/loki-stack \
  -n logging \
  -f "${HELM_DIR}/loki-values.yaml" \
  --wait --timeout 5m

echo ""
echo "=== All services deployed ==="
echo ""
echo "Grafana:    kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring"
echo "PostgreSQL: kubectl port-forward svc/postgres-postgresql 5432:5432 -n database"
echo "Demo app:   Build ./image-captioning → Jenkins (jenkins/Jenkinsfile), then ./scripts/08-upload-models.sh, then deploy stage (sets IRSA + S3 bucket from Terraform outputs)"
