locals {
  common_tags = merge(var.tags, {
    component  = "acceptance-test-harness"
    managed_by = "taipan-accelerator"
  })

  spokes = {
    a = {
      address_space = var.spoke_a_address_space
      name          = var.spoke_a_name
      subnet_prefix = var.spoke_a_subnet_prefix
      vm_name       = var.probe_a_vm_name
    }
    b = {
      address_space = var.spoke_b_address_space
      name          = var.spoke_b_name
      subnet_prefix = var.spoke_b_subnet_prefix
      vm_name       = var.probe_b_vm_name
    }
  }
}

data "azurerm_virtual_hub" "core" {
  name                = var.core_virtual_hub_name
  resource_group_name = var.core_resource_group_name
}

data "azurerm_firewall" "core" {
  name                = var.core_azure_firewall_name
  resource_group_name = var.core_resource_group_name
}

data "azurerm_firewall_policy" "core" {
  name                = var.core_firewall_policy_name
  resource_group_name = var.core_resource_group_name
}

resource "azurerm_resource_group" "test" {
  name     = var.test_resource_group_name
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_log_analytics_workspace" "test" {
  name                = var.log_analytics_workspace_name
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.common_tags
}

resource "azurerm_network_security_group" "probe_b" {
  name                = "nsg-${var.probe_b_vm_name}"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
  tags                = local.common_tags

  security_rule {
    name                       = "allow-spoke-a-http-test"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = var.spoke_a_address_space
    destination_address_prefix = "*"
  }
}

resource "azurerm_virtual_network" "spoke" {
  for_each = local.spokes

  name                = each.value.name
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
  address_space       = [each.value.address_space]
  tags                = local.common_tags
}

resource "azurerm_subnet" "probe" {
  for_each = local.spokes

  name                 = "snet-probe"
  resource_group_name  = azurerm_resource_group.test.name
  virtual_network_name = azurerm_virtual_network.spoke[each.key].name
  address_prefixes     = [each.value.subnet_prefix]
}

resource "azurerm_subnet_network_security_group_association" "probe_b" {
  subnet_id                 = azurerm_subnet.probe["b"].id
  network_security_group_id = azurerm_network_security_group.probe_b.id
}

resource "azurerm_virtual_hub_connection" "spoke" {
  for_each = local.spokes

  name                      = "conn-${each.value.name}-to-${var.core_virtual_hub_name}"
  virtual_hub_id            = data.azurerm_virtual_hub.core.id
  remote_virtual_network_id = azurerm_virtual_network.spoke[each.key].id

  internet_security_enabled = true
}

resource "azurerm_network_interface" "probe" {
  for_each = local.spokes

  name                = "nic-${each.value.vm_name}"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.probe[each.key].id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "probe" {
  for_each = local.spokes

  name                            = each.value.vm_name
  location                        = azurerm_resource_group.test.location
  resource_group_name             = azurerm_resource_group.test.name
  size                            = var.probe_vm_size
  admin_username                  = var.probe_vm_admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.probe[each.key].id]
  tags                            = local.common_tags

  admin_ssh_key {
    username   = var.probe_vm_admin_username
    public_key = var.probe_vm_admin_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = each.key == "b" ? base64encode(<<-CLOUD_INIT
    #!/bin/bash
    set -eu
    mkdir -p /opt/taipan-test
    echo 'taipan-vwan-acceptance-test' > /opt/taipan-test/index.html
    nohup /usr/bin/python3 -m http.server 8080 --directory /opt/taipan-test --bind 0.0.0.0 >/var/log/taipan-http-server.log 2>&1 &
  CLOUD_INIT
  ) : null
}

resource "azurerm_firewall_policy_rule_collection_group" "acceptance_test" {
  name               = "rcg-taipan-acceptance-test"
  firewall_policy_id = data.azurerm_firewall_policy.core.id
  priority           = 900

  network_rule_collection {
    action   = "Allow"
    name     = "allow-spoke-a-to-b-http"
    priority = 100

    rule {
      name                  = "allow-tcp-8080"
      protocols             = ["TCP"]
      source_addresses      = [var.spoke_a_address_space]
      destination_addresses = [var.spoke_b_address_space]
      destination_ports     = ["8080"]
    }
  }

  application_rule_collection {
    action   = "Allow"
    name     = "allow-approved-internet-https"
    priority = 200

    rule {
      name             = "allow-example-com-https"
      source_addresses = [var.spoke_a_address_space]
      destination_fqdns = [
        "www.example.com",
      ]

      protocols {
        type = "Https"
        port = 443
      }
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "firewall" {
  name                       = "diag-${var.core_azure_firewall_name}"
  target_resource_id         = data.azurerm_firewall.core.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.test.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
