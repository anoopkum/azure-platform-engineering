resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags

  lifecycle { ignore_changes = [tags] }
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = var.vnet_address_space
  # Azure default DNS (168.63.129.16) cannot resolve external CDN/TrafficManager chains.
  # Use public resolvers so VMSS agents can download packages from the internet.
  dns_servers = ["8.8.8.8", "8.8.4.4"]
  tags        = var.tags

  lifecycle { ignore_changes = [tags] }
}

resource "azurerm_subnet" "aks_subnet" {
  name                 = "${var.prefix}-aks-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = var.aks_subnet_prefixes
}

resource "azurerm_subnet" "agents_subnet" {
  name                 = "${var.prefix}-agents-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = var.agents_subnet_prefixes
}

resource "azurerm_public_ip" "nat_ip" {
  name                = "${var.prefix}-nat-ip"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags

  lifecycle { ignore_changes = [tags] }
}

resource "azurerm_nat_gateway" "nat" {
  name                = "${var.prefix}-nat"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  sku_name            = "Standard"
  tags                = var.tags

  lifecycle { ignore_changes = [tags] }
}

resource "azurerm_nat_gateway_public_ip_association" "nat_ip" {
  nat_gateway_id       = azurerm_nat_gateway.nat.id
  public_ip_address_id = azurerm_public_ip.nat_ip.id
}

resource "azurerm_subnet_nat_gateway_association" "agents" {
  subnet_id      = azurerm_subnet.agents_subnet.id
  nat_gateway_id = azurerm_nat_gateway.nat.id
}
