# Upstream Reference Register

## Microsoft Azure Verified Modules Virtual WAN pattern

- Source: `Azure/terraform-azurerm-avm-ptn-alz-connectivity-virtual-wan`
- Maintainer: Microsoft Azure Verified Modules
- Review snapshot: `116594239389f448c8db52b225566ef9e7ca68b5`
- Snapshot date: 2026-10-01
- Licence: MIT
- Decision: approved as the primary Terraform upstream reference

## Confirmed coverage

- Azure Landing Zones and Cloud Adoption Framework alignment
- Azure Virtual WAN and virtual hubs
- Secured hubs and Azure Firewall
- Multi-region topology example
- Route-map example
- Firewall-policy example
- Hub network-connection example
- Customer-provided firewall public-IP example
- Automated examples and tests

## Reuse rules

- Consume released upstream modules with pinned versions during implementation.
- Do not copy or vendor the upstream repository into this product.
- Preserve Microsoft licence and attribution when code or substantial adapted material is used.
- Review upstream releases before each Taipan accelerator release.
- Keep the local clone under `~/Workspace/References/avm-vwan` as read-only engineering reference.

## Taipan accelerator value

The accelerator adds the operating layer that a module alone does not provide:

- A business-led decision model for one, two, three, or four hubs.
- A validated architecture contract and profile configuration.
- Repeatable route, firewall, observability, resilience, and cost evidence.
- GitHub and Azure DevOps delivery templates with controlled promotion.
- Learner documentation that explains design decisions and troubleshooting.

## Next review
