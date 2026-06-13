# Azure Platform Engineering

A production-grade Platform Engineering reference implementation on Azure, covering:

- **AKS** — multi-node-pool Kubernetes cluster with Availability Zones, Azure CNI, RBAC
- **Terraform** — modular IaC for AKS, ACR, networking, Log Analytics
- **ArgoCD** — App-of-Apps GitOps pattern deploying ingress-nginx, cert-manager, external-secrets
- **Ansible** — self-hosted ADO agent provisioning, node baseline, ArgoCD CLI install
- **CI/CD** — GitHub Actions + Azure DevOps pipelines for Terraform and ArgoCD sync
- **Scripts** — cluster bootstrap, node drain, secret rotation, health check (Bash + Python)

## Repository Structure

```
azure-platform-engineering/
├── terraform/
│   ├── main.tf                    # Root module wiring
│   ├── variables.tf
│   ├── outputs.tf
│   ├── modules/
│   │   ├── aks/                   # AKS cluster + node pools + diagnostics
│   │   ├── networking/            # VNet, subnets, resource group
│   │   └── acr/                   # Container registry + AcrPull role
│   └── envs/
│       ├── dev/terraform.tfvars
│       └── prod/terraform.tfvars
├── argocd/
│   ├── bootstrap/                 # namespace, install script, app-of-apps manifest
│   └── apps/                      # ArgoCD Application manifests (nginx, cert-manager, ESO)
├── ansible/
│   ├── playbooks/                 # setup-ado-agents, setup-argocd-cli, baseline-nodes
│   ├── roles/
│   │   ├── ado-agent/             # Download, configure, start ADO agent as systemd service
│   │   ├── argocd-cli/            # Install ArgoCD CLI binary
│   │   └── node-baseline/         # Package updates, sysctl, swap disable
│   ├── inventory/hosts.ini
│   └── group_vars/all.yml
├── scripts/
│   ├── bootstrap-cluster.sh       # Get AKS creds → deploy ArgoCD → apply app-of-apps
│   ├── aks-node-drain.sh          # Safe cordon + drain with grace period
│   ├── rotate-secrets.sh          # Rotate Key Vault secret + trigger ESO refresh
│   └── health-check.py            # Check all nodes Ready + all deployments available
├── .github/workflows/
│   ├── terraform.yml              # Validate → Plan → Apply with OIDC auth
│   └── argocd-sync.yml            # Sync ArgoCD on argocd/** changes
└── azure-pipelines/
    ├── terraform-pipeline.yml     # Multi-stage ADO pipeline with self-hosted agents
    └── agent-setup.yml            # Ansible-driven self-hosted agent provisioning
```

## Quick Start

### 1. Provision Infrastructure

```bash
cd terraform
terraform init
terraform plan -var-file=envs/dev/terraform.tfvars -out=tfplan
terraform apply tfplan
```

### 2. Bootstrap ArgoCD

```bash
./scripts/bootstrap-cluster.sh ape-dev-aks ape-dev-rg
```

### 3. Provision Self-Hosted ADO Agents

```bash
ansible-playbook -i ansible/inventory/hosts.ini \
  ansible/playbooks/setup-ado-agents.yml
```

### 4. Cluster Health Check

```bash
python3 scripts/health-check.py
```

## Required GitHub Secrets

| Secret | Description |
|---|---|
| `AZURE_CLIENT_ID` | Managed Identity / App client ID (OIDC) |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription |
| `AKS_CLUSTER_NAME` | AKS cluster name |
| `AKS_RESOURCE_GROUP` | AKS resource group |
| `ARGOCD_SERVER` | ArgoCD server hostname |
| `ARGOCD_TOKEN` | ArgoCD API token |

## Required Azure DevOps Variables

| Variable | Description |
|---|---|
| `ADO_PAT` | Personal Access Token for agent registration |
| `KEYVAULT_NAME` | Key Vault holding the Ansible SSH key |
