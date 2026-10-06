# Start here

Created and maintained by Mohamed Elrehan for Taipan Academy.

## Current supported route

This version provides a disposable single-region Azure vWAN learning POC.
Production execution is disabled. Multi-region and CI/CD execution are future scope.

1. Prepare tools and state access using [onboarding](operations/CUSTOMER-ONBOARDING.md).
2. Follow the [POC quick-start](POC-QUICKSTART.md).
3. Use the [detailed runbook](POC-RUNBOOK.md) for configuration and recovery.
4. Review the plan before deployment.
5. Deploy and verify traffic, firewall telemetry, and workbook evidence.
6. Inspect the workbook before choosing Destroy or Keep.
7. Verify cleanup using Terraform state and Azure inventory.

## Matching defaults

For the beginner path, copy `infra/terraform/terraform.tfvars.example`
to the ignored local `infra/terraform/terraform.tfvars`.

These Taipan names match the harness example.
The Contoso profile is an alternative configuration, not a drop-in replacement:
its names must also be applied to the harness's core references.

## What the POC includes

- One Standard Virtual WAN and one virtual hub.
- Azure Firewall Standard, firewall policy, and routing intent.
- Two test spokes and two private probe VMs.
- Controlled private and HTTPS allow/deny tests.
- Log Analytics, a workbook, and local evidence reports.

VPN, ExpressRoute, production workloads, multi-region validation, and
intrusion-prevention tests are outside the current verified POC.

## Costs and ownership

The user owns the subscription, identities, Terraform state, resources, and costs.
The cost argument records approval; it does not enforce a spending cap.

Keep retains billable resources. Destroy removes the POC harness and core.
The separately bootstrapped state storage remains and may incur charges.

Do not remove the state backend while deployment or recovery still needs it.

## Design references

- [Topology](architecture/TOPOLOGY.md)
- [Architecture contract](architecture/ARCHITECTURE-CONTRACT.md)
- [Configuration profiles](../config/profiles/PROFILES.md)

Earlier production design documents describe future workflows.
Use the quick-start and runbook for current execution instructions.
