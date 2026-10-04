resource "azurerm_resource_group" "connectivity" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

module "virtual_wan" {
  source  = "Azure/avm-ptn-alz-connectivity-virtual-wan/azurerm"
  version = "0.17.2"

  enable_telemetry = var.enable_telemetry
  tags             = var.tags

  default_naming_convention = {
    virtual_wan_name     = var.virtual_wan_name
    virtual_hub_name     = var.virtual_hub_name
    firewall_name        = var.azure_firewall_name
    firewall_policy_name = var.firewall_policy_name
  }

  virtual_hubs = {
    primary = {
      enabled_resources = {
        firewall                              = true
        firewall_policy                       = true
        bastion                               = false
        virtual_network_gateway_express_route = false
        virtual_network_gateway_vpn           = false
        private_dns_zones                     = false
        private_dns_resolver                  = false
        sidecar_virtual_network               = false
      }

      is_primary                = true
      default_hub_address_space = var.virtual_hub_address_prefix
      default_parent_id         = azurerm_resource_group.connectivity.id
      location                  = var.location

      hub = {
        name           = var.virtual_hub_name
        address_prefix = var.virtual_hub_address_prefix
      }

      firewall = {
        name     = var.azure_firewall_name
        sku_name = "AZFW_Hub"
        sku_tier = var.azure_firewall_sku_tier
      }

      firewall_policy = {
        name                = var.firewall_policy_name
        resource_group_name = var.resource_group_name
        location            = var.location
        sku                 = var.azure_firewall_sku_tier
      }

      routing_intents = {
        default = {
          name = "routing-intent-primary"
          routing_policies = [
            {
              name                  = "private-traffic"
              destinations          = ["PrivateTraffic"]
              next_hop_firewall_key = "primary"
            },
            {
              name                  = "internet-traffic"
              destinations          = ["Internet"]
              next_hop_firewall_key = "primary"
            }
          ]
        }
      }
    }
  }
}
