#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${1:-cms-devops-dev-eks}"
REGION="${2:-ap-southeast-1}"

echo "=== Phase 2a: Configure kubectl ==="

echo "[1/2] Updating kubeconfig for cluster: ${CLUSTER_NAME}"
aws eks update-kubeconfig \
  --region "$REGION" \
  --name "$CLUSTER_NAME"

echo "[2/2] Verifying cluster access"
kubectl get nodes
echo ""
kubectl cluster-info

echo "=== kubectl configured ==="
