# Runbooks

## 1. Rotate a Key Vault Secret

Use when a secret (e.g. database password, API key) needs to be rolled.

```bash
./scripts/rotate-secrets.sh <vault-name> <secret-name> <new-value>
```

**What it does:**
1. Sets the new secret version in Key Vault
2. Annotates the relevant `ExternalSecret` resource to force an ESO refresh
3. Verifies the new Kubernetes Secret has the updated value

**Rollback:** In Key Vault, disable the new version and re-enable the previous version. ESO will pick it up on next refresh (or trigger manually with the annotation step).

---

## 2. Drain an AKS Node for Maintenance

Use before applying OS patches or decommissioning a node.

```bash
./scripts/aks-node-drain.sh <node-name>
```

**What it does:**
1. Cordons the node (no new pods scheduled)
2. Drains with `--ignore-daemonsets --delete-emptydir-data` and a 120s grace period
3. Prints confirmation when complete

**After maintenance:**
```bash
kubectl uncordon <node-name>
```

---

## 3. Bootstrap a New Cluster

Use after `terraform apply` creates a fresh AKS cluster.

```bash
./scripts/bootstrap-cluster.sh <cluster-name> <resource-group>
```

**What it does:**
1. Fetches AKS credentials via `az aks get-credentials`
2. Installs ArgoCD via Helm into the `argocd` namespace
3. Waits for ArgoCD deployments to be ready
4. Applies `argocd/bootstrap/namespace.yaml` and `argocd/bootstrap/app-of-apps.yaml`

**Prerequisites:** `kubectl`, `helm`, `argocd` CLI, and `az` CLI authenticated.

---

## 4. Cluster Health Check

Run at any time to get a quick view of node and deployment health.

```bash
python3 scripts/health-check.py
```

Returns exit code `0` if all nodes are `Ready` and all deployments have their desired replicas available. Non-zero otherwise (suitable for CI gates).

---

## 5. Provision / Re-provision Self-Hosted ADO Agents

Use when adding new agent VMs or after OS re-imaging.

```bash
# Update ansible/inventory/hosts.ini with new VM IPs first
ansible-playbook \
  -i ansible/inventory/hosts.ini \
  ansible/playbooks/setup-ado-agents.yml \
  --private-key ~/.ssh/ado-agents-key \
  --extra-vars "ado_pat=<your-pat>"
```

Or trigger the ADO pipeline `agent-setup.yml` which fetches the SSH key from Key Vault automatically.

**Agent registration variables required:**
- `ADO_ORG_URL` — e.g. `https://dev.azure.com/myorg`
- `ADO_POOL_NAME` — agent pool name in ADO
- `ADO_PAT` — PAT with Agent Pools (Read & Manage) scope

---

## 6. Sync ArgoCD Manually

Use if automated sync is paused or a deployment is stuck.

```bash
argocd app sync app-of-apps --force
argocd app sync ingress-nginx
argocd app sync cert-manager
argocd app sync external-secrets
```

Or trigger the GitHub Actions workflow `argocd-sync.yml` manually via `workflow_dispatch`.

---

## 7. Terraform Plan / Apply in CI

**GitHub Actions (OIDC):** Push to a branch with changes under `terraform/` — the `terraform.yml` workflow validates, plans (posts output as a PR comment), and on merge to `main` applies automatically.

**Azure DevOps:** Import `azure-pipelines/terraform-pipeline.yml`. The pipeline has an approval gate before the Apply stage. Required pipeline variables:

| Variable | Value |
|---|---|
| `TF_BACKEND_RESOURCE_GROUP` | `tfstate-rg` |
| `TF_BACKEND_STORAGE_ACCOUNT` | `tfstate<env>` |
| `TF_BACKEND_CONTAINER` | `tfstate` |
| `ENV` | `dev` or `prod` |

---

## 8. Rolling Node Pool Upgrade

1. Open the AKS blade in the Azure portal → **Node pools** → select pool → **Upgrade**.
2. Choose the target Kubernetes version (must match or be one minor version ahead of the control plane).
3. Monitor with:
   ```bash
   watch kubectl get nodes
   ```
4. Run health check after completion:
   ```bash
   python3 scripts/health-check.py
   ```

---

## 9. Add a New Application to GitOps

1. Create `argocd/apps/<app-name>.yaml` as an ArgoCD `Application` manifest (use `nginx.yaml` as a template).
2. Commit and push — the App-of-Apps will detect the new file and sync automatically.
3. If the app needs secrets: add an `ExternalSecret` in `kubernetes/manifests/` or in the app's own config repo.
4. If the app needs TLS: annotate the Ingress with `cert-manager.io/cluster-issuer: letsencrypt-prod`.

---

## 10. Emergency Access — Break-Glass

If ArgoCD or the OIDC provider is unavailable, use local kubeconfig with an AAD user that has `Azure Kubernetes Service Cluster Admin Role`:

```bash
az aks get-credentials \
  --resource-group <rg> \
  --name <cluster> \
  --admin   # uses cluster-admin cert, bypasses AAD
```

Revoke the `--admin` credential after the incident by rotating the cluster certificate authority:
```bash
az aks rotate-certs --resource-group <rg> --name <cluster>
```
