#!/usr/bin/env bash
set -euo pipefail

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

echo "--- Demo app (default namespace, after pipeline deploy) ---"
kubectl get pods -n default -l app.kubernetes.io/name=demo-app 2>/dev/null || echo "(not deployed yet)"
echo ""

echo "--- Ingress ---"
kubectl get ingress -A
echo ""
echo "If ADDRESS is empty for >5m: kubectl describe ingress -n default <demo-ingress-name>; kubectl logs -n kube-system deploy/aws-load-balancer-controller --tail=40"
echo "If ADDRESS is set but browser fails: ensure DNS (e.g. *.minhhuy.me) points to that ALB; run ./infrastructure/scripts/11-patch-ingress-acm-from-terraform.sh after first sync if HTTPS/cert missing."
echo ""

echo "--- All Pods Summary ---"
kubectl get pods -A --field-selector=status.phase!=Running 2>/dev/null | head -20 || echo "All pods are Running."
echo ""

echo "=== Verification complete ==="
echo ""
echo "Quick access (port-forward):"
echo "  Grafana:    kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring"
echo "  Demo app:   kubectl port-forward svc/demo-app 8081:80 -n default"
echo "  Jenkins:    runs on VPS (see infrastructure/scripts/06-setup-jenkins-vps.sh)"
