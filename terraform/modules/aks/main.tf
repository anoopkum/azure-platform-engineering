resource "azurerm_kubernetes_cluster" "aks_cluster" {
  name                = "${var.prefix}-aks"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "${var.prefix}-aks"
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier
  tags                = var.tags

  default_node_pool {
    name            = "system"
    node_count      = var.system_node_count
    vm_size         = var.system_vm_size
    vnet_subnet_id  = var.aks_subnet_id
    os_disk_size_gb = 50
    type            = "VirtualMachineScaleSets"
    zones           = ["1", "2", "3"]

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "calico"
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
  }

  oms_agent {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  azure_active_directory_role_based_access_control {
    managed            = true
    azure_rbac_enabled = true
  }

  lifecycle {
    ignore_changes = [default_node_pool[0].node_count]
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "user_pool" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks_cluster.id
  vm_size               = var.user_vm_size
  node_count            = var.user_node_count
  vnet_subnet_id        = var.aks_subnet_id
  zones                 = ["1", "2", "3"]
  mode                  = "User"
  tags                  = var.tags

  lifecycle {
    ignore_changes = [node_count]
  }
}

resource "azurerm_monitor_diagnostic_setting" "aks_diag" {
  name                       = "${var.prefix}-aks-diag"
  target_resource_id         = azurerm_kubernetes_cluster.aks_cluster.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "kube-apiserver"
  }
  enabled_log {
    category = "kube-controller-manager"
  }
  enabled_log {
    category = "kube-scheduler"
  }
  metric {
    category = "AllMetrics"
  }
}
