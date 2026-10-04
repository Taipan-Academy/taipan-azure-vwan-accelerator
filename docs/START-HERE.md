# Start Here

This repository delivers a reusable Azure vWAN accelerator, not a one-off demonstration.

The first implementation profile is one secured hub. It is deliberately designed so that the same architecture contract can later deploy two, three, or four hubs without duplicating modules.

Before infrastructure code is added, Sprint 0 validates the maintained Microsoft, Azure Verified Modules, and HashiCorp reference patterns. Their licences, versions, supported capabilities, and operating gaps are recorded as evidence.

Terraform is the primary deployment path. Bicep is an equivalent native Azure path. Only one engine can manage an environment at a time.

## Safety boundary

This public repository must never contain credentials, certificates, Terraform state, real subscription IDs, customer data, or production network ranges.
