#!/usr/bin/env bash
set -euo pipefail

# Match Helm release name (Argo CD Application name), e.g. image-captioning → deployments/services *-backend / *-frontend
REL="${HELM_RELEASE_NAME:-image-captioning}"

echo "=== Phase 5: Verification ==="
echo ""

echo "--- Cluster Nodes ---"
kubectl get nodes
echo ""

echo "--- ALB Controller ---"
kubectl get deployment -n kube-system aws-load-balancer-controller
echo ""

echo "--- Monitoring (monitoring namespace) ---"
kubectl get pods -n monitoring
echo ""

echo "--- Logging (logging namespace) ---"
kubectl get pods -n logging
echo ""

echo "--- Demo app (${REL}, default namespace, after pipeline deploy) ---"
kubectl get pods -n default -l "app.kubernetes.io/name=${REL}-backend" 2>/dev/null || true
kubectl get pods -n default -l "app.kubernetes.io/name=${REL}-frontend" 2>/dev/null || echo "(not deployed yet or different HELM_RELEASE_NAME)"
echo ""

echo "--- Ingress ---"
kubectl get ingress -A
echo ""
echo "If ADDRESS is empty for >5m: kubectl describe ingress -n default ${REL}-ingress; kubectl logs -n kube-system deploy/aws-load-balancer-controller --tail=40"
echo "If ADDRESS is set but browser fails: ensure DNS (e.g. *.minhhuy.me) points to that ALB; run ./infrastructure/scripts/11-patch-ingress-acm-from-terraform.sh after first sync if HTTPS/cert missing."
echo ""

echo "--- All Pods Summary ---"
kubectl get pods -A --field-selector=status.phase!=Running 2>/dev/null | head -20 || echo "All pods are Running."
echo ""

echo "=== Verification complete ==="
echo ""
echo "Quick access (port-forward):"
echo "  Grafana:    kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring"
echo "  API (${REL}-backend):    kubectl port-forward svc/${REL}-backend 8081:80 -n default"
echo "  UI (${REL}-frontend):    kubectl port-forward svc/${REL}-frontend 8080:80 -n default"
echo "  Jenkins:    runs on VPS (see infrastructure/scripts/06-setup-jenkins-vps.sh)"
