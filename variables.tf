variable "rg_name" {
  type        = string
  description = "Resource Group name where resources will be deployed"
}

variable "dns_rg_name" {
  type        = string
  description = "Resource Group name where DNS Zone will be deployed"
  default     = "p-dns-pri"
}

variable "key_vault_name" {
  type        = string
  description = "Override the name of the Key Vault"
  default     = null
}

variable "location" {
  type        = string
  description = "location where resources will be deployed"
  default     = "norwayeast"
}

variable "unique" {
  type        = string
  description = "A unique string that will be used in the names of the resources. Must be 6 characters long"
  validation {
    condition     = length(var.unique == null ? "123456" : var.unique) == 6
    error_message = "unique string has to be exactly 6 characters long"
  }
}

variable "subnet_id" {
  type        = string
  description = "The ID of the subnet where the Private Endpoint will be deployed"
  default = null
}

variable "sku_name" {
  type        = string
  default     = "standard"
  description = "The Name of the SKU used for this Key Vault. Possible values are standard and premium"
}

variable "enable_rbac_authorization" {
  type        = bool
  default     = true
  description = "Boolean flag to specify whether Azure Key Vault uses Role Based Access Control (RBAC) for authorization of data actions."
}

variable "soft_delete_retention_days" {
  type        = number
  default     = 90
  description = "The number of days that items should be retained for once soft-deleted. This value can be between 7 and 90 days."
}

variable "enabled_for_deployment" {
  type        = bool
  default     = false
  description = "Boolean flag to specify whether Azure Virtual Machines are permitted to retrieve certificates stored as secrets from the key vault."
}

variable "enabled_for_disk_encryption" {
  type        = bool
  default     = false
  description = "Boolean flag to specify whether Azure Disk Encryption is permitted to retrieve secrets from the vault and unwrap keys."
}

variable "enabled_for_template_deployment" {
  type        = bool
  default     = false
  description = "Boolean flag to specify whether Azure Resource Manager is permitted to retrieve secrets from the key vault."
}

variable "public_network_access_enabled" {
  type        = bool
  default     = true
  description = "Whether public network access is allowed for this Key Vault."
}

variable "purge_protection_enabled" {
  type        = bool
  default     = false
  description = "Is Purge Protection enabled for this Key Vault?"
}

variable "enable_private_endpoint" {
  type        = bool
  default     = true
  description = "Enable or disable private endpoint for the key vault. Defaults to true."
}

variable "network_acls" {
  description = "Network rules restricing access to the storage account."
  type = object({
    default_action = optional(string)
    bypass         = optional(string),
    ip_rules       = optional(list(string)),
    subnet_ids     = optional(list(string))
  })
  default = {
    default_action = "Deny"
    bypass         = "None"
  }
}
