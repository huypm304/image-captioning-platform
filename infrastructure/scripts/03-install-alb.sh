#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${1:-image-caption-dev-eks}"
REGION="${2:-ap-southeast-1}"
POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"

echo "=== Phase 2b: Install AWS Load Balancer Controller ==="

# Step 1: Associate OIDC provider
echo "[1/4] Associating IAM OIDC provider"
eksctl utils associate-iam-oidc-provider \
  --cluster "$CLUSTER_NAME" \
  --region "$REGION" \
  --approve

# Step 2: Download and create IAM policy (idempotent)
echo "[2/4] Creating IAM policy for ALB Controller"
POLICY_ARN=$(aws iam list-policies \
  --query "Policies[?PolicyName=='${POLICY_NAME}'].Arn" \
  --output text)

if [ -z "$POLICY_ARN" ]; then
  curl -fsSL -o /tmp/alb-iam-policy.json \
    https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.1/docs/install/iam_policy.json

  POLICY_ARN=$(aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document file:///tmp/alb-iam-policy.json \
    --query "Policy.Arn" \
    --output text)

  echo "  Created policy: ${POLICY_ARN}"
else
  echo "  Policy already exists: ${POLICY_ARN}"
fi

# Step 3: Create IAM service account
echo "[3/4] Creating IAM service account"
eksctl create iamserviceaccount \
  --cluster="$CLUSTER_NAME" \
  --region="$REGION" \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn="$POLICY_ARN" \
  --override-existing-serviceaccounts \
  --approve

# Step 4: Install ALB Controller via Helm
echo "[4/4] Installing ALB Controller via Helm"
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --wait

echo "=== ALB Controller installed ==="
kubectl get deployment -n kube-system aws-load-balancer-controller
