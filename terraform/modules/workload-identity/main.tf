resource "azurerm_user_assigned_identity" "identity" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "identity" {
  name                      = "${var.name}-federated"
  user_assigned_identity_id = azurerm_user_assigned_identity.identity.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = var.oidc_issuer_url
  subject                   = "system:serviceaccount:${var.service_account_namespace}:${var.service_account_name}"
}
