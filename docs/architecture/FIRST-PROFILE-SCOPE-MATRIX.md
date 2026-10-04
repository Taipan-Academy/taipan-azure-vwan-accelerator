# First Profile Scope Matrix

## Purpose

The first secured-hub profile must create only the services required for controlled route, firewall, and observability validation.

## Explicit AVM controls

| Capability | First profile decision | `enabled_resources` value |
|---|---|---|
| Azure Firewall | Included | `true` |
| Azure Firewall policy | Included | `true` |
| Azure Bastion | Excluded | `false` |
| ExpressRoute gateway | Excluded | `false` |
| VPN gateway | Excluded | `false` |
| Private DNS zones | Excluded | `false` |
| Private DNS resolver | Excluded | `false` |
| Sidecar virtual network | Excluded | `false` |

## Additional guardrails

- No ExpressRoute, VPN-site, point-to-site, or BGP connection configuration is accepted in the first profile.
- No Bastion, private DNS, or sidecar network is created implicitly.
- A dedicated test virtual network is introduced later through an explicit virtual-network connection for route and firewall evidence.

## Verification

Terraform plan must show only the approved Virtual WAN, virtual hub, Azure Firewall, firewall policy, diagnostics, and explicitly added test resources.

