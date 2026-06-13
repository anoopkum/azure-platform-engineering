#!/usr/bin/env bash
# Safely drains an AKS node for maintenance.
set -euo pipefail

NODE="${1:?Usage: $0 <node-name>}"

echo "Cordon node: ${NODE}"
kubectl cordon "${NODE}"

echo "Draining node: ${NODE}"
kubectl drain "${NODE}" \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=60 \
  --timeout=300s

echo "Node ${NODE} drained. Run the following to uncordon after maintenance:"
echo "  kubectl uncordon ${NODE}"
