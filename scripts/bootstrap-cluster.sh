#!/usr/bin/env bash
# Bootstraps ArgoCD onto a freshly provisioned AKS cluster.
set -euo pipefail

CLUSTER_NAME="${1:?Usage: $0 <cluster-name> <resource-group>}"
RESOURCE_GROUP="${2:?Usage: $0 <cluster-name> <resource-group>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "[1/4] Getting AKS credentials..."
az aks get-credentials --name "${CLUSTER_NAME}" --resource-group "${RESOURCE_GROUP}" --overwrite-existing

echo "[2/4] Verifying cluster connectivity..."
kubectl cluster-info

echo "[3/4] Bootstrapping ArgoCD..."
kubectl apply -f "${REPO_ROOT}/argocd/bootstrap/namespace.yaml"
kubectl apply -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.0/manifests/install.yaml"
kubectl rollout status deploy/argocd-server -n argocd --timeout=180s

echo "[4/4] Deploying App-of-Apps..."
kubectl apply -f "${REPO_ROOT}/argocd/bootstrap/app-of-apps.yaml"

echo ""
echo "Bootstrap complete."
echo "ArgoCD initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
echo ""
