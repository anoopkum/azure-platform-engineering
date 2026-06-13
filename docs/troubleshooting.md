# Troubleshooting

A living record of errors encountered in this project and how they were resolved.
Add new entries at the top of each section as you hit them.

---

## Terraform

### Error: `Backend configuration changed`
```
Error: Backend configuration changed
A change in the backend configuration has been detected, which may require
migrating or reconfiguring the state.
```
**Cause:** The storage account name or container in `main.tf` backend block does not match what was used during `terraform init`.
**Fix:**
```bash
terraform init -reconfigure
```
If migrating state from a different backend, use `-migrate-state` instead.

---

### Error: `storage account not found` during `terraform init`
```
Error: Failed to get existing workspaces: storage: service returned error:
StatusCode=404
```
**Cause:** The Terraform state storage account (`tfstatedev`) does not exist yet.
**Fix:** Create it manually before running `terraform init`:
```bash
az group create -n tfstate-rg -l uksouth
az storage account create -n tfstatedev -g tfstate-rg --sku Standard_LRS
az storage container create -n tfstate --account-name tfstatedev
```

---

### Error: `subscription_id` is not set
```
Error: "subscription_id": required field is not set
```
**Cause:** `terraform/envs/dev/terraform.tfvars` still has the placeholder value `YOUR_SUBSCRIPTION_ID`.
**Fix:** Replace it with your actual subscription ID:
```bash
az account show --query id -o tsv
```
Then update [terraform/envs/dev/terraform.tfvars](../terraform/envs/dev/terraform.tfvars) line 1.

---

### Error: `AuthorizationFailed` on `terraform apply`
```
Error: creating/updating Resource Group: authorization.RoleAssignmentsClient#Create:
Failure responding to request: StatusCode=403
```
**Cause:** The service principal or managed identity running Terraform does not have Contributor (or Owner) on the target subscription/resource group.
**Fix:** Assign the role in Azure:
```bash
az role assignment create \
  --assignee <client-id> \
  --role Contributor \
  --scope /subscriptions/<subscription-id>
```

---

### Error: `compute.VirtualMachineScaleSetsClient` quota exceeded
```
Error: creating Node Pool: compute.VirtualMachineScaleSetsClient#CreateOrUpdate:
Failure: Code="OperationNotAllowed" Message="Operation results in exceeding quota limits"
```
**Cause:** The subscription does not have enough vCPU quota for the requested VM size in the target region.
**Fix:** Request a quota increase in the Azure portal under **Subscriptions → Usage + Quotas**, or reduce `system_node_count` / `user_node_count` in `terraform.tfvars`.

---

### Error: `Provider produced inconsistent result after apply` (AKS node count)
```
Error: Provider produced inconsistent result after apply
```
**Cause:** AKS auto-scaler changes node count between plan and apply; the `ignore_changes` lifecycle block handles this but an initial apply without it will error.
**Fix:** The `lifecycle { ignore_changes = [node_count] }` blocks in `modules/aks/main.tf` prevent this. If you see it, run `terraform apply` again — it resolves on the next run.

---

## GitHub Actions / OIDC

### Error: `AADSTS700213: No matching federated identity record` for `environment:dev`
```
Error: AADSTS700213: No matching federated identity record found for presented assertion
subject 'repo:anoopkum/azure-platform-engineering:environment:dev'.
```
**Cause:** Jobs that specify `environment: dev` in the workflow emit a JWT with subject `repo:<org>/<repo>:environment:dev`, not `ref:refs/heads/main`. A separate federated credential is required for each subject pattern.
**Fix:** Add a federated credential for the environment subject:
```bash
az ad app federated-credential create \
  --id <AZURE_CLIENT_ID> \
  --parameters '{
    "name": "github-env-dev",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:anoopkum/azure-platform-engineering:environment:dev",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```
Three federated credentials are required in total:
| Name | Subject |
|---|---|
| `github-main` | `repo:anoopkum/azure-platform-engineering:ref:refs/heads/main` |
| `github-pull-req` | `repo:anoopkum/azure-platform-engineering:pull_request` |
| `github-env-dev` | `repo:anoopkum/azure-platform-engineering:environment:dev` |

---

### Error: `Error building ARM Config: Authenticating using the Azure CLI is only supported as a User`
```
Error: Error building ARM Config: Authenticating using the Azure CLI is only
supported as a User (not a Service Principal).
```
**Cause:** Using `azure/login@v2` action and then running Terraform. The azurerm provider cannot use Azure CLI authentication when running as a Service Principal — it requires `ARM_` environment variables set directly.
**Fix:** Remove the `azure/login@v2` step and set `ARM_` vars at the workflow `env` level instead:
```yaml
env:
  ARM_USE_OIDC: "true"
  ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
  ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
  ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```
The provider requests a GitHub OIDC token directly using `ACTIONS_ID_TOKEN_REQUEST_URL` and `ACTIONS_ID_TOKEN_REQUEST_TOKEN`, which GitHub injects automatically when `permissions.id-token: write` is set.

---

### Error: `AADSTS70021: No matching federated identity record found`
```
Error: AADSTS70021: No matching federated identity record found for presented assertion.
```
**Cause:** The federated credential on the App Registration does not match the branch, repo, or audience in the GitHub Actions token.
**Fix:** In Azure → App Registration → Certificates & Secrets → Federated credentials, verify:
- **Issuer:** `https://token.actions.githubusercontent.com`
- **Subject:** `repo:anoopkum/azure-platform-engineering:ref:refs/heads/main`
- **Audience:** `api://AzureADTokenExchange`

---

### Error: `Resource not accessible by integration` on PR comment
```
Error: Resource not accessible by integration
```
**Cause:** The workflow `permissions` block is missing `pull-requests: write`.
**Fix:** Already present in `.github/workflows/terraform.yml`. If you add new workflows, include:
```yaml
permissions:
  id-token: write
  contents: read
  pull-requests: write
```

---

### Terraform plan not posting as PR comment
**Cause:** The plan step succeeds but the comment step is skipped — usually because `github.event_name != 'pull_request'`.
**Fix:** The comment step should be gated on `if: github.event_name == 'pull_request'`. Check the workflow condition matches your trigger.

---

## AKS

### Error: `K8sVersionNotSupported` — version is LTS-only
```
Error: creating Kubernetes Cluster: unexpected status 400 (400 Bad Request)
"code": "K8sVersionNotSupported"
"message": "Managed cluster ape-dev-aks is on version 1.31.x, which is only
available for Long-Term Support (LTS)..."
```
**Cause:** In some regions (e.g. `uksouth`), older patch versions of Kubernetes are restricted to LTS/Premium tier clusters only. Using them on a Standard tier cluster is blocked by the API.
**Fix:** Check the available non-LTS versions in your region and use the one with `KubernetesOfficial` support plan:
```bash
az aks get-versions --location uksouth --output json | python3 -c "
import json,sys
for v in json.load(sys.stdin)['values']:
    plans = v.get('capabilities',{}).get('supportPlan',[])
    if 'KubernetesOfficial' in plans:
        print(v['version'], plans)
"
```
Update `kubernetes_version` in `terraform/envs/dev/terraform.tfvars` and `terraform/modules/aks/variables.tf` to the supported version (currently `1.36`).

---

### Error: `azure_active_directory_role_based_access_control` — Missing required argument
```
Error: Missing required argument
"azure_active_directory_role_based_access_control.0.admin_group_object_ids":
one of admin_group_object_ids, tenant_id must be specified
```
**Cause:** In azurerm `~> 4.0`, the `azure_active_directory_role_based_access_control` block requires either `admin_group_object_ids` or `tenant_id`. The `managed` and `azure_rbac_enabled` fields alone are no longer sufficient. Azure RBAC is always enabled by default in v4.
**Fix:** Remove the entire `azure_active_directory_role_based_access_control` block from `modules/aks/main.tf`. Azure RBAC is on by default — the block is only needed when restricting access to specific AAD groups.

**History of this error across provider versions:**

| Provider | Config | Result |
|---|---|---|
| `~> 3.100` | `managed=true` + `azure_rbac_enabled=true` | AKS API rejects `managed` as deprecated |
| `~> 3.100` | `azure_rbac_enabled=true` only | Provider requires `managed` as part of `one of` |
| `~> 4.0` | `azure_rbac_enabled=true` only | Provider requires `admin_group_object_ids` or `tenant_id` |
| `~> 4.0` | Block removed entirely | ✅ Works — Azure RBAC on by default |

---

### Error: `ServiceCidrOverlapExistingSubnetsCidr`
```
Error: creating Kubernetes Cluster: unexpected status 400 (400 Bad Request)
"code": "ServiceCidrOverlapExistingSubnetsCidr"
"message": "The specified service CIDR 10.0.0.0/16 is conflicted with an
existing subnet CIDR 10.0.1.0/24."
```
**Cause:** AKS defaults `service_cidr` to `10.0.0.0/16` which conflicts with the VNet address space (also `10.0.0.0/16`). The service CIDR must not overlap with any subnet in the VNet.
**Fix:** Explicitly set non-overlapping CIDRs in the `network_profile` block in `modules/aks/main.tf`:
```hcl
network_profile {
  network_plugin    = "azure"
  network_policy    = "calico"
  load_balancer_sku = "standard"
  outbound_type     = "loadBalancer"
  service_cidr      = "172.16.0.0/16"
  dns_service_ip    = "172.16.0.10"
}
```
CIDR allocation for this project:
| Range | Purpose |
|---|---|
| `10.0.0.0/16` | VNet address space |
| `10.0.1.0/24` | AKS nodes subnet |
| `10.0.2.0/24` | ADO agents subnet |
| `172.16.0.0/16` | Kubernetes service CIDR |
| `172.16.0.10` | CoreDNS service IP |

---

### Error: `StorageAccountAlreadyTaken` when creating Terraform state backend
```
(StorageAccountAlreadyTaken) The storage account named tfstatedev is already taken.
```
**Cause:** Azure storage account names are globally unique across all subscriptions. A generic name like `tfstatedev` is already taken.
**Fix:** Use a unique name incorporating your subscription ID suffix:
```bash
az storage account create \
  --name tfstateape27320543dev \
  --resource-group tfstate-rg \
  --sku Standard_LRS \
  --allow-blob-public-access false
```
Update the storage account name in `terraform/envs/dev/backend.conf`.

---

### Error: `Terraform exited with code 3` on `terraform fmt -check`
```
modules/aks/main.tf
Error: Terraform exited with code 3.
```
**Cause:** `terraform fmt` found formatting inconsistencies (misaligned `=` signs, wrong indentation). Exit code 3 means files need reformatting.
**Fix:** Run `terraform fmt -recursive` locally before pushing:
```bash
cd terraform && terraform fmt -recursive
```
Then commit the formatted files. The CI `fmt -check` step will pass on the next push.

---

### Error: Variable interpolation in Terraform backend block
```
Error: Variables not allowed
Variables may not be used here.
```
**Cause:** Terraform backend blocks do not support variable interpolation (`${var.env}`). Backend configuration is parsed before variables are available.
**Fix:** Use a partial backend config file per environment, passed via `-backend-config` at init time:
```bash
terraform init -backend-config="envs/dev/backend.conf"
```
Where `envs/dev/backend.conf` contains just `storage_account_name = "tfstateape27320543dev"`.

---

### Error: `Evicted` pods after node drain
```
Warning  Evicted  pod/foo-xxx  The node was low on resource: memory.
```
**Cause:** `aks-node-drain.sh` uses `--delete-emptydir-data` which removes emptyDir volumes. Pods using local storage are evicted.
**Fix:** This is expected behaviour for stateless pods. For stateful pods, ensure they use PersistentVolumeClaims backed by Azure Disk/File before draining.

---

### Error: `Unable to connect to the server: dial tcp` after `az aks get-credentials`
```
Unable to connect to the server: dial tcp <ip>:443: i/o timeout
```
**Cause:** The AKS API server is not reachable — either a private cluster with no VPN, or a network policy/NSG blocking port 443.
**Fix:**
1. Confirm the cluster is not private: `az aks show -g <rg> -n <name> --query apiServerAccessProfile`
2. Check your client IP is in the authorised IP ranges if `enablePrivateCluster: false` but `authorizedIpRanges` is set.
3. For a private cluster, connect from a VM inside the VNet or use `az aks command invoke`.

---

### Error: `pods "argocd-server-xxx" not found` during bootstrap
```
Error from server (NotFound): pods "argocd-server-xxx" not found
```
**Cause:** `bootstrap-cluster.sh` ran `kubectl rollout status` before ArgoCD pods were scheduled.
**Fix:** Re-run the script — it is idempotent. Or wait and apply manually:
```bash
kubectl rollout status deploy/argocd-server -n argocd --timeout=300s
kubectl apply -f argocd/bootstrap/app-of-apps.yaml
```

---

### Nodes stuck in `NotReady` after upgrade
**Cause:** A node upgrade left a node cordoned. Verify with `kubectl get nodes`.
**Fix:**
```bash
kubectl uncordon <node-name>
```
If the node remains unhealthy after 5 minutes, delete it — AKS VMSS will reprovision it:
```bash
kubectl delete node <node-name>
```

---

## ArgoCD

### App stuck in `OutOfSync` / sync loop
**Cause:** A resource in the cluster was mutated outside of Git (e.g. a manual `kubectl edit`), and `selfHeal: true` keeps reverting it.
**Fix:** Either commit the intended state to Git, or disable selfHeal temporarily:
```bash
argocd app set <app-name> --self-heal=false
```
Re-enable after the investigation is complete.

---

### Error: `ComparisonError: failed to load target state: rpc error`
```
ComparisonError: failed to load target state: rpc error: code = Unknown
desc = `helm template` error ...
```
**Cause:** The Helm chart version in `argocd/apps/<app>.yaml` is unreachable or the chart repo is down.
**Fix:** Check the repo URL and `targetRevision` in the Application manifest. Verify the chart exists:
```bash
helm repo add <name> <url>
helm search repo <chart> --versions | head
```

---

### ArgoCD UI not accessible after bootstrap
**Cause:** No Ingress or LoadBalancer is yet provisioned for the ArgoCD server.
**Fix:** Use port-forward for immediate access:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
Then open `https://localhost:8080`. Get the initial admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

---

## cert-manager

### Certificate stuck in `False / Issuing`
```
$ kubectl get certificate -A
NAMESPACE   NAME   READY   SECRET   AGE
workloads   foo    False   foo-tls  5m
```
**Cause:** The DNS-01 challenge failed. Common reasons: workload identity not wired, DNS zone name mismatch, or propagation delay.
**Fix:**
```bash
kubectl describe certificaterequest -n <namespace>
kubectl describe challenge -n <namespace>
```
Check that:
1. The `ClusterIssuer` has the correct `subscriptionID`, `resourceGroupName`, and `hostedZoneName`.
2. The cert-manager ServiceAccount annotation `azure.workload.identity/client-id` matches the Managed Identity that has **DNS Zone Contributor** on the zone.
3. The pod label `azure.workload.identity/use: "true"` is present — check with `kubectl get po -n cert-manager --show-labels`.

---

### Error: `failed to determine ACME account` on first run
```
E0101 failed to determine ACME account: Get "https://acme-v02...": context deadline exceeded
```
**Cause:** cert-manager cannot reach the Let's Encrypt ACME endpoint — usually an egress firewall or missing internet access on the user node pool.
**Fix:** Confirm outbound internet access from the cluster:
```bash
kubectl run curl --image=curlimages/curl --restart=Never -it --rm \
  -- curl -I https://acme-v02.api.letsencrypt.org/directory
```

---

## External Secrets Operator

### Secret not syncing — `SecretSyncedError`
```
SecretSyncedError: could not get secret ... 403 Forbidden
```
**Cause:** The workload identity used by ESO does not have **Key Vault Secrets User** on the vault.
**Fix:**
```bash
az role assignment create \
  --assignee <eso-managed-identity-client-id> \
  --role "Key Vault Secrets User" \
  --scope /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<vault>
```

---

### `ClusterSecretStore` in `Invalid` state
```
$ kubectl get clustersecretstore azure-keyvault
NAME             AGE   STATUS
azure-keyvault   2m    Invalid
```
**Cause:** The vault URL in `kubernetes/manifests/secret-store.yaml` still contains the `${KEYVAULT_NAME}` placeholder, or the vault does not exist yet.
**Fix:** Replace the placeholder with the actual vault name and re-apply:
```bash
kubectl apply -f kubernetes/manifests/secret-store.yaml
```

---

### ExternalSecret refreshes but Kubernetes Secret is unchanged
**Cause:** ESO caches the secret and the `refreshInterval` has not elapsed.
**Fix:** Force an immediate refresh by annotating the ExternalSecret:
```bash
kubectl annotate externalsecret <name> -n <namespace> \
  force-sync="$(date +%s)" --overwrite
```
This is what `scripts/rotate-secrets.sh` does automatically.

---

## Ansible

### `UNREACHABLE` for all hosts
```
fatal: [10.0.4.x]: UNREACHABLE! => {"msg": "Failed to connect to the host via ssh"}
```
**Cause:** The SSH private key path is wrong, the key has wrong permissions, or the VMs are not yet provisioned.
**Fix:**
```bash
chmod 600 /path/to/key
ansible -i ansible/inventory/hosts.ini ado_agents -m ping --private-key /path/to/key
```
Ensure the agent VMs exist in the `agents-subnet` (`10.0.4.0/24`) and have the SSH port open in their NSG.

---

### ADO agent registers but shows `Offline` in the pool
**Cause:** The `ADO_PAT` used during registration expired, or the agent service failed to start.
**Fix:** SSH into the VM and check the agent service:
```bash
sudo systemctl status vsts.agent.*
sudo journalctl -u vsts.agent.* -n 50
```
Re-run the `setup-ado-agents.yml` playbook with a fresh PAT.

---

### `FAILED - RETRYING` on package install tasks
**Cause:** The VM has no internet access or the package mirror is temporarily unavailable.
**Fix:** Verify outbound internet from the agent VM:
```bash
curl -I https://packages.microsoft.com
```
If the cluster uses a private egress (UDR / Azure Firewall), ensure `packages.microsoft.com` and `download.visualstudio.microsoft.com` are in the allowed FQDNs.

---

## Azure DevOps Pipelines

### Pipeline fails with `No hosted parallelism has been purchased`
```
No hosted parallelism has been purchased or granted. To request a free parallelism
grant, please fill out the following form ...
```
**Cause:** New ADO organisations need a free parallelism grant or must use self-hosted agents.
**Fix:** Either request a free grant (takes 2–3 business days) or point the pipeline at your self-hosted pool:
```yaml
pool:
  name: your-self-hosted-pool-name
```

---

### `azure-service-connection` not found
```
There was a resource authorization issue: "The pipeline is not valid.
Job Terraform: Step AzureCLI input ConnectedServiceNameARM references service
connection azure-service-connection which could not be found."
```
**Cause:** The ADO service connection named `azure-service-connection` has not been created.
**Fix:** In ADO → Project Settings → Service Connections → New → Azure Resource Manager. Name it exactly `azure-service-connection`.

---

### Terraform Apply stage skipped in ADO pipeline
**Cause:** The approval gate for the Apply stage was not configured, so the stage was skipped rather than waiting.
**Fix:** In the ADO environment linked to the Apply stage, add an **Approvals** check under Environments → `<env>` → Approvals and Checks.

---

## General

### `kubectl` commands fail with `You must be logged in to the server (Unauthorized)`
**Cause:** The AAD token in the kubeconfig has expired (tokens last 1 hour).
**Fix:**
```bash
kubelogin convert-kubeconfig -l azurecli
az account get-access-token
```
Or re-fetch credentials:
```bash
az aks get-credentials --resource-group <rg> --name <cluster> --overwrite-existing
```

---

### `health-check.py` exits non-zero but cluster looks healthy
**Cause:** A deployment is in a rollout (not all replicas available yet) or a namespace was recently created and pods are still pulling images.
**Fix:** Wait 2–3 minutes and re-run. If the issue persists:
```bash
kubectl get deployments -A | grep -v "Running\|Available"
kubectl describe deployment <name> -n <namespace>
```
