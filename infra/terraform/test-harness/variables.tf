variable "location" {
  description = "Azure region for the temporary test resources."
  type        = string
}

variable "test_resource_group_name" {
  description = "Resource group for independently destroyable test resources."
  type        = string
}

variable "log_analytics_workspace_name" {
  description = "Name of the temporary Log Analytics workspace."
  type        = string
}

variable "core_resource_group_name" {
  description = "Resource group that contains the deployed secured vWAN core."
  type        = string
}

variable "core_virtual_hub_name" {
  description = "Name of the deployed virtual hub."
  type        = string
}

variable "core_azure_firewall_name" {
  description = "Name of the deployed Azure Firewall in the secured virtual hub."
  type        = string
}

variable "core_firewall_policy_name" {
  description = "Name of the deployed Azure Firewall Policy."
  type        = string
}

variable "spoke_a_name" {
  description = "Name of the source test spoke VNet."
  type        = string
}

variable "spoke_a_address_space" {
  description = "CIDR address space for the source test spoke VNet."
  type        = string
}

variable "spoke_a_subnet_prefix" {
  description = "CIDR prefix for the source probe subnet."
  type        = string
}

variable "spoke_b_name" {
  description = "Name of the destination test spoke VNet."
  type        = string
}

variable "spoke_b_address_space" {
  description = "CIDR address space for the destination test spoke VNet."
  type        = string
}

variable "spoke_b_subnet_prefix" {
  description = "CIDR prefix for the destination probe subnet."
  type        = string
}

variable "probe_a_vm_name" {
  description = "Name of the source probe VM."
  type        = string
}

variable "probe_b_vm_name" {
  description = "Name of the destination probe VM."
  type        = string
}

variable "probe_vm_size" {
  description = "Azure VM size for both temporary probe VMs."
  type        = string
  default     = "Standard_B1s"
}

variable "probe_vm_admin_username" {
  description = "Linux administrator name for the temporary probe VMs."
  type        = string
  default     = "taipanadmin"
}

variable "probe_vm_admin_ssh_public_key" {
  description = "Dedicated temporary SSH public key for VM provisioning. Do not use a personal or GitHub key."
  type        = string
}

variable "log_retention_days" {
  description = "Log Analytics retention period for the temporary test workspace."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
}

variable "tags" {
  description = "Tags applied to test resources."
  type        = map(string)
  default     = {}
}
