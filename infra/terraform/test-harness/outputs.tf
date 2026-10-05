output "log_analytics_workspace_id" {
  description = "Resource ID of the temporary acceptance-test Log Analytics workspace."
  value       = azurerm_log_analytics_workspace.test.id
}

output "probe_a_private_ip" {
  description = "Private IP address of the source probe VM."
  value       = azurerm_network_interface.probe["a"].private_ip_address
}

output "probe_b_private_ip" {
  description = "Private IP address of the destination probe VM."
  value       = azurerm_network_interface.probe["b"].private_ip_address
}

output "test_resource_group_name" {
  description = "Resource group that can be independently destroyed after evidence collection."
  value       = azurerm_resource_group.test.name
}

output "virtual_hub_connection_ids" {
  description = "Virtual hub connection IDs created for the two test spokes."
  value       = { for key, connection in azurerm_virtual_hub_connection.spoke : key => connection.id }
}

output "log_analytics_workspace_guid" {
  description = "Workspace GUID used by Azure CLI log queries."
  value       = azurerm_log_analytics_workspace.test.workspace_id
}
