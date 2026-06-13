variable "prefix" {
  type = string
}

variable "location" {
  type    = string
  default = "uksouth"
}

variable "resource_group_name" {
  type = string
}

variable "kubernetes_version" {
  type    = string
  default = "1.36"
}

variable "sku_tier" {
  type    = string
  default = "Standard"
}

variable "aks_subnet_id" {
  type = string
}

variable "system_node_count" {
  type    = number
  default = 2
}

variable "system_vm_size" {
  type    = string
  default = "Standard_D2s_v3"
}

variable "user_node_count" {
  type    = number
  default = 2
}

variable "user_vm_size" {
  type    = string
  default = "Standard_D4s_v3"
}

variable "log_analytics_workspace_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
