output "cluster_id" {
  value = azurerm_kubernetes_cluster.aks_cluster.id
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.aks_cluster.name
}

output "kube_config" {
  value     = azurerm_kubernetes_cluster.aks_cluster.kube_config_raw
  sensitive = true
}

output "kubelet_identity_object_id" {
  value = azurerm_kubernetes_cluster.aks_cluster.kubelet_identity[0].object_id
}

output "oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.aks_cluster.oidc_issuer_url
}
