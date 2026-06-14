terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Partial backend config — storage_account_name is passed via -backend-config
  # at init time: terraform init -backend-config=envs/<env>/backend.conf
  backend "azurerm" {
    resource_group_name = "tfstate-rg"
    container_name      = "tfstate"
    key                 = "azure-platform-engineering.tfstate"
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  use_oidc        = true
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = "${var.prefix}-law"
  location            = var.location
  resource_group_name = module.networking.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags

  lifecycle { ignore_changes = [tags] }
}

module "networking" {
  source              = "./modules/networking"
  prefix              = var.prefix
  location            = var.location
  resource_group_name = "${var.prefix}-rg"
  tags                = local.tags
}

module "aks" {
  source                     = "./modules/aks"
  prefix                     = var.prefix
  location                   = var.location
  resource_group_name        = module.networking.resource_group_name
  aks_subnet_id              = module.networking.aks_subnet_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  kubernetes_version         = var.kubernetes_version
  system_node_count          = var.system_node_count
  user_node_count            = var.user_node_count
  tags                       = local.tags
}

module "acr" {
  source                         = "./modules/acr"
  acr_name                       = "${replace(var.prefix, "-", "")}acr${var.env}"
  resource_group_name            = module.networking.resource_group_name
  location                       = var.location
  aks_kubelet_identity_object_id = module.aks.kubelet_identity_object_id
  tags                           = local.tags
}

module "ado_agents" {
  source              = "./modules/vm"
  name                = "${var.prefix}-ado-agents"
  resource_group_name = module.networking.resource_group_name
  location            = var.location
  subnet_id           = module.networking.agents_subnet_id
  ssh_public_key      = var.ssh_public_key
  instance_count      = var.ado_agent_count
  tags                = local.tags
}

module "workload_identity_external_secrets" {
  source                    = "./modules/workload-identity"
  name                      = "${var.prefix}-wi-external-secrets"
  location                  = var.location
  resource_group_name       = module.networking.resource_group_name
  oidc_issuer_url           = module.aks.oidc_issuer_url
  service_account_namespace = "external-secrets"
  service_account_name      = "external-secrets"
  tags                      = local.tags
}

module "workload_identity_cert_manager" {
  source                    = "./modules/workload-identity"
  name                      = "${var.prefix}-wi-cert-manager"
  location                  = var.location
  resource_group_name       = module.networking.resource_group_name
  oidc_issuer_url           = module.aks.oidc_issuer_url
  service_account_namespace = "cert-manager"
  service_account_name      = "cert-manager"
  tags                      = local.tags
}

module "keyvault" {
  source              = "./modules/keyvault"
  name                = "${replace(var.prefix, "-", "")}kv${var.env}"
  location            = var.location
  resource_group_name = module.networking.resource_group_name
  secrets_reader_principal_ids = {
    external-secrets = module.workload_identity_external_secrets.principal_id
  }
  tags = local.tags
}

locals {
  tags = merge(var.tags, {
    environment = var.env
    managed_by  = "terraform"
    project     = "azure-platform-engineering"
  })
}
