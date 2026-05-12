#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
K8S_DIR="${REPO_ROOT}/deploy/kubernetes"
PROM_VALUES="${REPO_ROOT}/observability/prometheus/values.yaml"
LOKI_VALUES="${REPO_ROOT}/observability/loki/values.yaml"

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
  -f "${PROM_VALUES}" \
  --wait --timeout 5m

# Logging: Promtail → Loki; Grafana uses this via prometheus values additionalDataSources
echo "[4/4] Installing Loki stack"
helm upgrade --install loki grafana/loki-stack \
  -n logging \
  -f "${LOKI_VALUES}" \
  --wait --timeout 5m

echo ""
echo "=== All services deployed ==="
echo ""
echo "Grafana:    kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring"
echo "Demo app:   Jenkins (ci/jenkins/Jenkinsfile) → ECR + GitOps; infrastructure/scripts/08-upload-models.sh syncs models/ to S3"
