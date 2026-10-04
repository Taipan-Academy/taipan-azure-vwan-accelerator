# Taipan Azure vWAN Accelerator

An evidence-first Azure Virtual WAN and Azure Firewall accelerator for learning and controlled enterprise adoption.

## Current status

Sprint 0 is in progress. No Azure resources are deployed from this repository.

## Scope

- One secured Azure vWAN hub that can be used as a small production profile when its resilience limits are accepted.
- Optional two-, three-, and four-hub profiles for resilience, geography, latency, and regulatory needs.
- Azure Firewall, Virtual WAN route tables, routing intent, and auditable traffic controls.
- Terraform as the primary implementation path and an equivalent Bicep path.
- Azure Monitor, Log Analytics, Grafana, and optional Loki integration.
- GitHub and Azure DevOps delivery patterns with approvals and evidence.

## Engineering principles

- Start from maintained Microsoft, Azure Verified Modules, and HashiCorp patterns.
- Create custom code only for genuine enterprise operating gaps.
- Never let Terraform and Bicep manage the same Azure resources in one environment.
- Never commit secrets, certificates, Terraform state, or real environment values.
- Automation accelerates delivery but does not remove architecture, security, cost, or change approval.

## Repository map

- `docs/` — architecture, decisions, operations, tests, and learner guidance
- `infra/` — Terraform and Bicep implementations
- `config/` — topology profiles and validation schemas
