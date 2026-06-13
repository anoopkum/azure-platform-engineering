#!/usr/bin/env bash
set -euo pipefail

ARGOCD_VERSION="v2.11.0"
NAMESPACE="argocd"

kubectl apply -f namespace.yaml

kubectl apply -n "${NAMESPACE}" \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "Waiting for ArgoCD server to be ready..."
kubectl rollout status deploy/argocd-server -n "${NAMESPACE}" --timeout=120s

kubectl apply -f app-of-apps.yaml

echo "ArgoCD bootstrapped. Access via:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
