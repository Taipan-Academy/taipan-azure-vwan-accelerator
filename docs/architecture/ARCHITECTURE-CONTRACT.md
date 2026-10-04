# Architecture Contract

## First validated profile

The first Taipan profile is a controlled Azure Virtual WAN deployment for a learning environment or approved proof of concept. It is not a production deployment until its named approvals and evidence exist.

- One Standard Azure Virtual WAN.
- One virtual hub in a selected Azure region.
- Azure Firewall and firewall policy for secured-hub traffic control.
- A dedicated test virtual network connection for route and inspection evidence.
- Azure Monitor diagnostic settings as the initial observability control.
- Terraform as the only infrastructure engine for this environment.

## Exclusions from the first profile

- No ExpressRoute, site-to-site VPN, point-to-site VPN, or branch connectivity.
- No third-party network virtual appliance.
- No customer workload, customer data, or production secret.
- No simultaneous Bicep ownership of Terraform-managed resources.

## Scale contract

A second hub is introduced only when the resilience, regional, regulatory, or latency requirement is approved.

Three or four hubs use the same profile contract and deployment modules. They are not separate copied designs.

## Control gates

An approved address plan, naming standard, resource tags, cost estimate, identity model, and firewall policy baseline are required before the first apply.

Terraform plan, route tests, firewall tests, logs, and teardown evidence are required before a profile is marked proven.

## Entry condition for implementation

The next task is to convert this contract into a non-production single-hub configuration schema and validate it locally without Azure deployment.
