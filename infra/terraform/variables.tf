variable "location" {
  type        = string
  description = "Azure region for the first secured hub."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Name of the connectivity resource group."
  nullable    = false
}

variable "virtual_wan_name" {
  type        = string
  description = "Name of the Azure Virtual WAN."
  nullable    = false
}

variable "virtual_hub_name" {
  type        = string
  description = "Name of the primary virtual hub."
  nullable    = false
}

variable "virtual_hub_address_prefix" {
  type        = string
  description = "Address prefix allocated to the primary virtual hub."
  nullable    = false
}

variable "azure_firewall_name" {
  type        = string
  description = "Name of the Azure Firewall in the secured virtual hub."
  nullable    = false
}

variable "firewall_policy_name" {
  type        = string
  description = "Name of the Azure Firewall Policy."
  nullable    = false
}

variable "azure_firewall_sku_tier" {
  type        = string
  description = "Azure Firewall tier for the secured virtual hub."
  default     = "Standard"
  nullable    = false

  validation {
    condition     = contains(["Standard", "Premium"], var.azure_firewall_sku_tier)
    error_message = "azure_firewall_sku_tier must be Standard or Premium."
  }
}

variable "enable_telemetry" {
  type        = bool
  description = "Whether the upstream AVM telemetry is enabled."
  default     = false
  nullable    = false
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to Taipan-managed resources."
  default     = {}
  nullable    = false
}

variable "hub_address_space" {
  type        = string
  description = "Parent address space used by the AVM module for hub-related allocation."
  nullable    = false
}
