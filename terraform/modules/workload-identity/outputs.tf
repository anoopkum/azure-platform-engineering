output "client_id" {
  value = azurerm_user_assigned_identity.identity.client_id
}

output "principal_id" {
  value = azurerm_user_assigned_identity.identity.principal_id
}
