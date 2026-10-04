# Bicep Upstream Reference

## Decision

Microsoft's `Azure/bicep-registry-modules` repository is the approved Bicep upstream reference for Taipan Accelerator version 1.

## Evidence

- Maintainer: Microsoft.
- Licence: MIT.
- Verified module source paths: `avm/res/network/virtual-wan`, `avm/res/network/virtual-hub`, and `avm/res/network/azure-firewall`.
- Review date: 2026-10-04.

## Consumption rules

- Import published AVM Bicep registry modules with explicit versions.
- Never deploy directly from a mutable Git branch such as `main`.
- Keep the chosen module versions in the release evidence and review them before upgrades.
- Use Bicep only in environments designated for Bicep; never manage the same Azure resources with Terraform.

## What Taipan adds

- A reusable topology-profile contract for one to four hubs.
- CI/CD, approval, validation, observability, and operating evidence.
- Clear learner guidance that distinguishes a demonstrable POC from an approved production deployment.

## Next action

Validate the installed Azure CLI Bicep version on the build VM before writing the Bicep implementation.
