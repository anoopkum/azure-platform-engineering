# Architecture

## Overview

This repository is a production-grade Platform Engineering reference on Azure. It provisions a multi-node-pool AKS cluster, wires GitOps via ArgoCD, provisions self-hosted ADO agents via Ansible, and delivers full CI/CD via both GitHub Actions and Azure DevOps Pipelines.

## Component Map

```
┌─────────────────────────────────────────────────────────────────┐
│                        Azure Subscription                        │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Resource Group: <prefix>-rg                             │   │
│  │                                                          │   │
│  │  ┌──────────────┐   ┌───────────────────────────────┐   │   │
│  │  │  VNet        │   │  AKS Cluster                  │   │   │
│  │  │  10.0.0.0/16 │   │                               │   │   │
│  │  │              │   │  ┌────────────┐ ┌──────────┐  │   │   │
│  │  │  aks-subnet  │──▶│  │System Pool │ │User Pool │  │   │   │
│  │  │  10.0.0.0/22 │   │  │(Standard_D │ │(Standard_│  │   │   │
│  │  │              │   │  │ 2s_v3 x2)  │ │D4s_v3 x2)│  │   │   │
│  │  │  agents-     │   │  └────────────┘ └──────────┘  │   │   │
│  │  │  subnet      │   │                               │   │   │
│  │  │  10.0.4.0/24 │   │  Azure CNI + Calico policy    │   │   │
│  │  └──────────────┘   │  AAD RBAC + Workload Identity │   │   │
│  │                      │  OMS diagnostics → Log Analytics│  │   │
│  │  ┌──────────────┐   └───────────────────────────────┘   │   │
│  │  │  ACR          │                                        │   │
│  │  │  (Basic/Std)  │◀── AcrPull via kubelet identity       │   │
│  │  └──────────────┘                                        │   │
│  │                                                          │   │
│  │  ┌──────────────┐   ┌──────────────────────────────┐    │   │
│  │  │  Key Vault   │   │  Log Analytics Workspace      │    │   │
│  │  │  (secrets +  │   │  (kube-apiserver, controller, │    │   │
│  │  │   SSH keys)  │   │   scheduler + AllMetrics)     │    │   │
│  │  └──────────────┘   └──────────────────────────────┘    │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘

           GitOps (ArgoCD App-of-Apps)
           ┌──────────────────────────────────────────┐
           │  argocd/apps/                            │
           │  ├── ingress-nginx (v4.10.1)             │
           │  ├── cert-manager (v1.14.5) + ACME DNS01 │
           │  └── external-secrets (0.9.18) + KV      │
           └──────────────────────────────────────────┘
```

## Terraform Modules

| Module | Resources | Key Outputs |
|---|---|---|
| `networking` | Resource group, VNet (`10.0.0.0/16`), AKS subnet (`10.0.0.0/22`), agents subnet (`10.0.4.0/24`) | `resource_group_name`, `aks_subnet_id`, `agents_subnet_id` |
| `aks` | AKS cluster, system node pool (AZs 1-2-3), user node pool, diagnostic settings | `cluster_id`, `kube_config`, `kubelet_identity_object_id` |
| `acr` | Container Registry, AcrPull role assignment to kubelet identity | `acr_login_server` |

Root `main.tf` also provisions a Log Analytics Workspace used by the AKS OMS agent and diagnostic settings.

## GitOps Pattern

ArgoCD is bootstrapped manually via `scripts/bootstrap-cluster.sh`, which:
1. Fetches AKS credentials
2. Installs ArgoCD via Helm into the `argocd` namespace
3. Applies `argocd/bootstrap/app-of-apps.yaml`

The App-of-Apps watches `argocd/apps/` and reconciles ingress-nginx, cert-manager, and external-secrets automatically. All three are configured with `automated: { prune: true, selfHeal: true }`.

## Secrets Flow

```
Azure Key Vault
     │
     │  (Workload Identity — OIDC federated credential)
     ▼
External Secrets Operator (ClusterSecretStore: azure-keyvault)
     │
     │  ExternalSecret resources in each workload namespace
     ▼
Kubernetes Secrets  ──▶  Pods
```

The `workload-identity.yaml` manifest wires the ESO and cert-manager ServiceAccounts to their respective Azure Managed Identities via the `azure.workload.identity/client-id` annotation.

## TLS Flow

cert-manager is configured with two ClusterIssuers (`letsencrypt-staging`, `letsencrypt-prod`). Both use DNS-01 challenges against Azure DNS via a dedicated workload identity, so no HTTP-01 ingress rule is needed. Ingress resources reference the issuer via annotation:

```yaml
cert-manager.io/cluster-issuer: letsencrypt-prod
```

## CI/CD

| Pipeline | Trigger | Stages |
|---|---|---|
| GitHub Actions `terraform.yml` | push to `terraform/**` or `main` | validate → plan (PR comment) → apply (main only) |
| GitHub Actions `argocd-sync.yml` | push to `argocd/**` | hard refresh → sync → wait healthy |
| ADO `terraform-pipeline.yml` | manual / branch | validate → plan → apply (approval gate) |
| ADO `agent-setup.yml` | manual | Ansible provisions self-hosted agents from Key Vault SSH key |

## Network Topology

| CIDR | Purpose |
|---|---|
| `10.0.0.0/16` | VNet address space |
| `10.0.0.0/22` | AKS nodes (1022 usable) |
| `10.0.4.0/24` | Self-hosted ADO agents (254 usable) |
| `10.0.5.0/24` | Reserved for future use |

## Identity Model

| Principal | Type | Role |
|---|---|---|
| AKS kubelet identity | System-assigned MI | `AcrPull` on ACR |
| external-secrets SA | Workload Identity (OIDC) | Key Vault Secrets User |
| cert-manager SA | Workload Identity (OIDC) | DNS Zone Contributor (scoped) |
| GitHub Actions | Federated credential (OIDC) | Contributor on subscription (scoped to TF state RG + AKS RG) |
