variable "name" {
  type        = string
  description = "Name of the managed identity"
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "oidc_issuer_url" {
  type        = string
  description = "AKS OIDC issuer URL"
}

variable "service_account_namespace" {
  type        = string
  description = "Kubernetes namespace of the service account"
}

variable "service_account_name" {
  type        = string
  description = "Kubernetes service account name"
}

variable "tags" {
  type    = map(string)
  default = {}
}
