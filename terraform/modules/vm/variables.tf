variable "name" {
  type        = string
  description = "Name of the VM Scale Set"
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "vm_size" {
  type    = string
  default = "Standard_B2s"
}

variable "instance_count" {
  type        = number
  default     = 2
  description = "Initial number of agent instances"
}

variable "admin_username" {
  type    = string
  default = "azureuser"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for VM access"
}

variable "tags" {
  type    = map(string)
  default = {}
}
