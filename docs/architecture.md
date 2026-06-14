# Architecture

## Overview

This repository is a production-grade Platform Engineering reference on Azure. It provisions a multi-node-pool AKS cluster, wires GitOps via ArgoCD, provisions self-hosted ADO agents via Ansible, and delivers full CI/CD via GitHub Actions (Terraform) and Azure DevOps Pipelines (app builds).

---

## Dev Environment (Current)

### Component Map

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Azure Subscription                           │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │  Resource Group: ape-dev-rg                                    │ │
│  │                                                                │ │
│  │  ┌──────────────┐   ┌─────────────────────────────────────┐   │ │
│  │  │  VNet        │   │  AKS Cluster (ape-dev-aks)           │   │ │
│  │  │  10.0.0.0/16 │   │                                     │   │ │
│  │  │              │   │  ┌────────────┐  ┌───────────────┐  │   │ │
│  │  │  aks-subnet  │──▶│  │System Pool │  │  User Pool    │  │   │ │
│  │  │  10.0.0.0/22 │   │  │(D2s_v3 x2) │  │  (D4s_v3 x2) │  │   │ │
│  │  │              │   │  └────────────┘  └───────────────┘  │   │ │
│  │  │  agents-     │   │                                     │   │ │
│  │  │  subnet      │   │  Namespaces:                        │   │ │
│  │  │  10.0.4.0/24 │   │  ├── argocd      (GitOps engine)   │   │ │
│  │  │              │   │  ├── ingress-nginx(LB + routing)    │   │ │
│  │  │  NAT GW ─────┼──▶│  ├── cert-manager(TLS automation)  │   │ │
│  │  │  (outbound)  │   │  └── workloads   (hello-platform)  │   │ │
│  │  └──────────────┘   └─────────────────────────────────────┘   │ │
│  │                                                                │ │
│  │  ┌──────────────┐   ┌──────────────────────────────────────┐  │ │
│  │  │  ACR          │   │  Log Analytics Workspace              │  │ │
│  │  │  apedevacrdev │◀──│  (kube-apiserver, controller,        │  │ │
│  │  │  (AcrPull via │   │   scheduler, AllMetrics)             │  │ │
│  │  │  kubelet MI)  │   └──────────────────────────────────────┘  │ │
│  │  └──────────────┘                                              │ │
│  └────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

### CI/CD Pipeline (hello-platform)

```
Developer pushes code
        │
        ▼
GitHub (anoopkum/azure-platform-engineering)
        │
        ▼
ADO Pipeline — self-hosted agents (VMSS in agents-subnet)
  ┌─────────────────────────────────────────────────────────┐
  │  Stage 1: UnitTest                                      │
  │    pytest + coverage report (must be ≥80%)              │
  ├─────────────────────────────────────────────────────────┤
  │  Stage 2: Security (parallel)                           │
  │    SAST — bandit (medium/high severity)                 │
  │    SCA  — pip-audit (known CVEs in dependencies)        │
  ├─────────────────────────────────────────────────────────┤
  │  Stage 3: BuildAndScan                                  │
  │    docker build (python:3.12-slim, UID 1001)            │
  │    Trivy scan (CRITICAL/HIGH, --ignore-unfixed)         │
  │    docker push → apedevacrdev.azurecr.io/hello-platform │
  ├─────────────────────────────────────────────────────────┤
  │  Stage 4: Deploy (main branch only)                     │
  │    sed patch image tag in helm/values.yaml              │
  │    git commit + push → triggers ArgoCD                  │
  └─────────────────────────────────────────────────────────┘
        │
        ▼
ArgoCD (auto-sync, prune, selfHeal)
        │
        ▼
AKS — workloads namespace
  hello-platform Deployment (2 replicas)
        │
        ▼
nginx Ingress → TLS termination (self-signed cert) → Pod (gunicorn:8080)
```

### TLS Flow (Dev — Self-Signed)

```
kubernetes/manifests/selfsigned-issuer.yaml
  └── selfsigned-cluster-issuer (selfSigned: {})
        └── selfsigned-ca Certificate (isCA: true) → Secret: selfsigned-ca-secret
              └── dev-ca-issuer (ClusterIssuer, ca: selfsigned-ca-secret)
                    └── cert-manager issues hello-platform-tls Secret
                          └── nginx Ingress uses it for HTTPS on hello-platform.dev.local
```

No public DNS required. Add to `/etc/hosts`:
```
20.77.137.230 hello-platform.dev.local
```

### Request Flow (Dev)

```
Browser (Mac)
    │  DNS resolved via /etc/hosts → 20.77.137.230
    ▼
Azure Load Balancer (20.77.137.230) — port 443
    │  TCP passthrough to nginx ingress pods
    ▼
nginx Ingress Controller
    │  Matches Host: hello-platform.dev.local
    │  Terminates TLS using hello-platform-tls secret
    ▼
hello-platform Service (ClusterIP, port 80)
    │  Load balances across 2 pods
    ▼
hello-platform Pod (port 8080, gunicorn, UID 1001)
    │  readOnlyRootFilesystem: true + emptyDir at /tmp
    ▼
Flask app → { "app": "hello-platform", "env": "dev", "version": "1.0.0" }
```

---

## Prod Architecture (Future)

### Three-Tier Design

```
──────────────────────────────────────────────────────────────
TIER 1 — Edge & Security
──────────────────────────────────────────────────────────────
  User Browser
      │
      ▼
  Azure Front Door (global anycast, CDN, SSL offload)
      │  Real public cert (Let's Encrypt or DigiCert)
      ▼
  WAF (OWASP ruleset, bot protection, rate limiting)
      │  Blocks SQLi, XSS, bad bots before reaching cluster
      ▼
  Palo Alto NGFW (Hub VNet)
      │  Deep packet inspection, threat prevention
      │  SSL decryption, east-west traffic policy
      │  Only Front Door origin IPs can reach the LB

──────────────────────────────────────────────────────────────
TIER 2 — Application (AKS — Spoke VNet, peered to Hub)
──────────────────────────────────────────────────────────────
      ▼
  nginx Ingress (routes by hostname/path)
      ▼
  Azure API Management (APIM)
      │  OAuth2/JWT validation
      │  Rate limiting, quotas per consumer
      │  Request/response transformation
      │  API versioning and developer portal
      ▼
  App Pods — workloads namespace
      │  Services communicate via Service Mesh (Istio/Linkerd)
      │  mTLS for east-west traffic
      │  Palo Alto enforces pod-to-pod network policy

──────────────────────────────────────────────────────────────
TIER 3 — Data (Private Endpoints only, no public access)
──────────────────────────────────────────────────────────────
      ▼
  Azure SQL / CosmosDB / PostgreSQL  ← Private Endpoint
  Azure Cache for Redis              ← Private Endpoint
  Azure Blob Storage                 ← Private Endpoint
  Azure Key Vault                    ← Private Endpoint (secrets, certs)
```

### Key Security Rules Between Tiers

| From | To | Allowed |
|---|---|---|
| Internet | Tier 1 (Front Door) | 80, 443 |
| Tier 1 (Palo Alto) | Tier 2 (nginx Ingress) | 443 only, Front Door IP ranges |
| Tier 2 (pods) | Tier 3 (data) | Private Endpoint ports only, no public internet |
| Tier 3 | Anywhere | Never initiates outbound |
| Pod to Pod (east-west) | Same namespace | Istio mTLS + NetworkPolicy |
| Pod to Pod (cross-namespace) | Other namespace | Palo Alto + NetworkPolicy deny-by-default |

### Prod Additions vs Dev

| Component | Dev | Prod |
|---|---|---|
| TLS | Self-signed (dev-ca-issuer) | Public cert via Front Door |
| Ingress | nginx (direct LB) | nginx behind Palo Alto + Front Door |
| Auth | None | APIM OAuth2/JWT |
| Secrets | Kubernetes secrets | Azure Key Vault via External Secrets Operator |
| DNS | /etc/hosts | Azure DNS public zone |
| Monitoring | Log Analytics | Log Analytics + Azure Monitor + Alerts |
| Image scanning | Trivy in pipeline | Trivy + Azure Defender for Containers |
| Agent provisioning | Ansible K8s Job | Same, with Key Vault SSH key rotation |

---

## Terraform Modules

| Module | Resources | Key Outputs |
|---|---|---|
| `networking` | Resource group, VNet (`10.0.0.0/16`), AKS subnet (`10.0.0.0/22`), agents subnet (`10.0.4.0/24`), NAT Gateway | `resource_group_name`, `aks_subnet_id`, `agents_subnet_id` |
| `aks` | AKS cluster, system node pool (AZs 1-2-3), user node pool, diagnostic settings | `cluster_id`, `kube_config`, `kubelet_identity_object_id` |
| `acr` | Container Registry, AcrPull role assignment to kubelet identity | `acr_login_server` |

---

## GitOps Pattern

ArgoCD is bootstrapped via `scripts/bootstrap-cluster.sh`:
1. Fetches AKS credentials
2. Installs ArgoCD via Helm into the `argocd` namespace
3. Applies `argocd/bootstrap/app-of-apps.yaml`

The App-of-Apps watches `argocd/apps/` and reconciles ingress-nginx, cert-manager, and hello-platform automatically. All apps use `automated: { prune: true, selfHeal: true }`.

---

## Identity Model

| Principal | Type | Role |
|---|---|---|
| AKS kubelet identity | System-assigned MI | `AcrPull` on ACR |
| GitHub Actions | Federated credential (OIDC) | Contributor scoped to AKS + TF state RGs |
| ADO pipeline | Service connection (OIDC) | `azure-connection` — ACR login, AKS access |

---

## Network Topology

| CIDR | Purpose |
|---|---|
| `10.0.0.0/16` | VNet address space |
| `10.0.0.0/22` | AKS nodes (1022 usable) |
| `10.0.4.0/24` | Self-hosted ADO agents (254 usable) |
| `172.16.0.0/16` | Kubernetes service CIDR |
| `172.16.0.10` | CoreDNS service IP |
