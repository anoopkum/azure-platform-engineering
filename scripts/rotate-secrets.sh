#!/usr/bin/env bash
# Rotates a secret in Azure Key Vault and triggers a Kubernetes secret refresh
# via External Secrets Operator by annotating the ExternalSecret resource.
set -euo pipefail

KEYVAULT_NAME="${1:?Usage: $0 <keyvault-name> <secret-name> <namespace> <external-secret-name>}"
SECRET_NAME="${2:?}"
NAMESPACE="${3:?}"
ES_NAME="${4:?}"

NEW_VALUE=$(openssl rand -base64 32 | tr -d '\n')

echo "Updating secret '${SECRET_NAME}' in Key Vault '${KEYVAULT_NAME}'..."
az keyvault secret set \
  --vault-name "${KEYVAULT_NAME}" \
  --name "${SECRET_NAME}" \
  --value "${NEW_VALUE}" \
  --output none

echo "Triggering ExternalSecret refresh in namespace '${NAMESPACE}'..."
kubectl annotate externalsecret "${ES_NAME}" \
  -n "${NAMESPACE}" \
  force-sync="$(date +%s)" \
  --overwrite

echo "Secret rotated and refresh triggered."
