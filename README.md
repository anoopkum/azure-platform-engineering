# Azure Platform Engineering

A production-grade Platform Engineering reference implementation on Azure, covering:

- **AKS** — multi-node-pool Kubernetes cluster with Availability Zones, Azure CNI, RBAC
- **Terraform** — modular IaC for AKS, ACR, networking, Log Analytics
- **ArgoCD** — App-of-Apps GitOps pattern deploying ingress-nginx, cert-manager, workload apps
- **Ansible** — self-hosted ADO agent provisioning, node baseline, Docker install
- **CI/CD** — GitHub Actions (Terraform) + Azure DevOps Pipelines (app CI) + ArgoCD (CD)
- **hello-platform** — Python/Flask reference app with full security scanning pipeline

## Repository Structure

```
azure-platform-engineering/
├── terraform/
│   ├── main.tf                    # Root module wiring
│   ├── variables.tf
│   ├── outputs.tf
│   ├── modules/
│   │   ├── aks/                   # AKS cluster + node pools + diagnostics
│   │   ├── networking/            # VNet, subnets, NAT gateway, resource group
│   │   └── acr/                   # Container registry + AcrPull role
│   └── envs/
│       ├── dev/terraform.tfvars
│       └── prod/terraform.tfvars
├── apps/
│   └── hello-platform/
│       ├── app/main.py            # Flask app — /, /health, /ready endpoints
│       ├── Dockerfile             # python:3.12-slim, non-root UID 1001, gunicorn
│       ├── requirements.txt
│       ├── requirements-dev.txt   # pytest, bandit, pip-audit
│       ├── tests/
│       └── helm/                  # Helm chart — Deployment, Service, Ingress, Certificate
├── argocd/
│   ├── bootstrap/                 # namespace, install script, app-of-apps manifest
│   └── apps/                      # ArgoCD Application manifests
│       └── hello-platform.yaml    # Auto-sync, prune, selfHeal
├── ansible/
│   ├── playbooks/                 # setup-ado-agents, install-docker
│   ├── roles/
│   │   ├── ado-agent/             # Download, configure, start ADO agent as systemd service
│   │   ├── docker/                # Install Docker CE, add azureuser to docker group
│   │   └── node-baseline/         # Package updates, sysctl, swap disable
│   ├── inventory/hosts.ini
│   └── group_vars/all.yml
├── azure-pipelines/
│   ├── hello-platform.yml         # 4-stage app CI: UnitTest → SAST → SCA → BuildAndScan
│   └── terraform-pipeline.yml     # Multi-stage Terraform: Validate → Plan → Apply
├── kubernetes/
│   └── manifests/
│       ├── selfsigned-issuer.yaml # Self-signed CA issuer chain for dev TLS
│       └── ansible/               # K8s Job for Ansible-based agent provisioning
├── scripts/
│   ├── bootstrap-cluster.sh       # Get AKS creds → deploy ArgoCD → apply app-of-apps
│   ├── aks-node-drain.sh          # Safe cordon + drain with grace period
│   ├── rotate-secrets.sh          # Rotate Key Vault secret + trigger ESO refresh
│   └── health-check.py            # Check all nodes Ready + all deployments available
├── .github/workflows/
│   └── terraform.yml              # Validate → Plan → Apply with OIDC auth
└── docs/
    ├── architecture.md
    ├── runbooks.md
    └── troubleshooting.md
```

## Quick Start

### 1. Provision Infrastructure

```bash
cd terraform
terraform init -backend-config="envs/dev/backend.conf"
terraform plan -var-file=envs/dev/terraform.tfvars -out=tfplan
terraform apply tfplan
```

### 2. Bootstrap ArgoCD

```bash
./scripts/bootstrap-cluster.sh ape-dev-aks ape-dev-rg
```

### 3. Provision Self-Hosted ADO Agents

```bash
kubectl apply -f kubernetes/manifests/ansible/ansible-job.yaml
```

### 4. Apply cert-manager Self-Signed Issuer (dev TLS)

```bash
kubectl apply -f kubernetes/manifests/selfsigned-issuer.yaml
```

### 5. Cluster Health Check

```bash
python3 scripts/health-check.py
```

### 6. Access hello-platform (dev)

Add to `/etc/hosts`:
```
20.77.137.230 hello-platform.dev.local
```
Then open `https://hello-platform.dev.local` in your browser (accept the self-signed cert warning).

## CI/CD Flow

```
Code push to GitHub
        │
        ├─► GitHub Actions (terraform/** changes)
        │       Validate → Plan → Apply (OIDC auth)
        │
        └─► ADO Pipeline (apps/hello-platform/** changes)
                Stage 1: Unit Tests + coverage (pytest, >80% required)
                Stage 2: SAST (bandit) + SCA (pip-audit) — parallel
                Stage 3: Docker build → Trivy scan (--ignore-unfixed) → ACR push
                Stage 4: Patch image tag in values.yaml → git push
                                │
                                └─► ArgoCD detects values.yaml change
                                        Auto-sync → Helm render → AKS deploy
```

## Required GitHub Secrets

| Secret | Description |
|---|---|
| `AZURE_CLIENT_ID` | Managed Identity / App client ID (OIDC) |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription |

## Required Azure DevOps Variables / Service Connections

| Name | Type | Description |
|---|---|---|
| `azure-connection` | Service connection | Azure Resource Manager (OIDC) for ACR login |
| `ADO_PAT` | Secret variable | PAT for agent registration |
| `KEYVAULT_NAME` | Variable | Key Vault holding the Ansible SSH key |
