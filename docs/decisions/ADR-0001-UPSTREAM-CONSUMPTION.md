# ADR-0001: Consume Microsoft AVM Virtual WAN pattern without vendoring it

## Status

Accepted for accelerator version 1.

## Context

The Taipan accelerator requires a supported Azure Virtual WAN foundation that works for both a simple single-hub profile and a scalable multi-region profile.

Microsoft's Azure Verified Modules Virtual WAN pattern was reviewed at commit `116594239389f448c8db52b225566ef9e7ca68b5`. Its MIT licence, minimal configuration example, full multi-region example, tests, secured-hub firewall capability, route-map example, and network-connection example were confirmed.

## Decision

- Use the Microsoft AVM Virtual WAN pattern as the primary Terraform upstream dependency.
- Consume released, version-pinned modules. Do not copy or vendor the Microsoft source into this repository.
- Build a Taipan configuration contract above the module using stable hub keys and named deployment profiles.
- Start with a single secured-hub profile, then scale to two, three, or four hubs through configuration rather than separate implementations.
- Treat Terraform as the primary deployment engine. Bicep will be an equivalent, separately managed deployment path.
- Record upstream version, licence, and validation evidence in every Taipan release.

## Production control

The reviewed Microsoft full multi-region example references a helper module from a mutable `main` branch. Taipan will not use mutable Git branch references in deployment dependencies.

Every module, provider, and helper dependency used by a Taipan deployment must have a deliberate version or immutable commit pin. Upgrades must pass plan, test, and review gates before promotion.

## Consequences

- Upstream improvements can be adopted without maintaining a fork.
- Taipan users receive a stable and auditable configuration interface.
- The accelerator documents enterprise decisions and operational evidence that upstream infrastructure modules do not own.
- Upstream compatibility is reviewed before each accelerator release.
