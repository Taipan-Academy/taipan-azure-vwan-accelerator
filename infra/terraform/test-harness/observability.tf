locals {
  poc_firewall_workbook_json = replace(
    replace(
      file("${path.module}/observability/firewall-workbook.json"),
      "__POC_WORKSPACE_RESOURCE_ID__",
      azurerm_log_analytics_workspace.test.id
    ),
    "__POC_FIREWALL_RESOURCE_ID__",
    data.azurerm_firewall.core.id
  )
}

resource "azurerm_application_insights_workbook" "poc_firewall" {
  name                = uuidv5("url", "${azurerm_resource_group.test.id}/taipan-firewall-workbook")
  resource_group_name = data.azurerm_firewall.core.resource_group_name
  location            = azurerm_resource_group.test.location
  display_name        = "Taipan vWAN POC - Firewall Observability"
  category            = "workbook"
  source_id           = lower(azurerm_log_analytics_workspace.test.id)
  data_json           = local.poc_firewall_workbook_json
  tags                = local.common_tags

  depends_on = [azurerm_monitor_diagnostic_setting.firewall]
}

output "observability_workbook_resource_id" {
  description = "Azure resource ID of the POC firewall workbook."
  value       = azurerm_application_insights_workbook.poc_firewall.id
}

output "observability_url" {
  description = "Azure portal resource link for opening the POC workbook."
  value       = "https://portal.azure.com/#resource${azurerm_application_insights_workbook.poc_firewall.id}"
}
