variable "name" {
  type        = string
  description = "Key Vault name (globally unique, 3-24 chars)"
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "secrets_reader_principal_ids" {
  type        = map(string)
  description = "Map of label -> principal_id to grant Key Vault Secrets User role"
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
