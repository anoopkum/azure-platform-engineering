variable "prefix" {
  type        = string
  description = "Naming prefix for all resources"
}

variable "location" {
  type    = string
  default = "uksouth"
}

variable "resource_group_name" {
  type = string
}

variable "vnet_address_space" {
  type    = list(string)
  default = ["10.0.0.0/16"]
}

variable "aks_subnet_prefixes" {
  type    = list(string)
  default = ["10.0.1.0/24"]
}

variable "agents_subnet_prefixes" {
  type    = list(string)
  default = ["10.0.2.0/24"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
