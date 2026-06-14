variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID"
}

variable "prefix" {
  type        = string
  description = "Naming prefix (e.g. ape-dev, ape-prod)"
}

variable "env" {
  type        = string
  description = "Environment short name: dev | staging | prod"
}

variable "location" {
  type    = string
  default = "uksouth"
}

variable "kubernetes_version" {
  type    = string
  default = "1.36"
}

variable "system_node_count" {
  type    = number
  default = 2
}

variable "user_node_count" {
  type    = number
  default = 2
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for ADO agent VMs"
}

variable "ado_agent_count" {
  type        = number
  default     = 2
  description = "Initial number of ADO self-hosted agent instances"
}

variable "tags" {
  type    = map(string)
  default = {}
}
