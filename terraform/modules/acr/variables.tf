variable "acr_name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type    = string
  default = "uksouth"
}

variable "sku" {
  type    = string
  default = "Standard"
}

variable "aks_kubelet_identity_object_id" {
  type        = string
  description = "Object ID of the AKS kubelet managed identity for AcrPull role assignment"
}

variable "tags" {
  type    = map(string)
  default = {}
}
