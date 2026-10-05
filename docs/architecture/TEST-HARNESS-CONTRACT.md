# Optional acceptance-test harness

The acceptance-test harness proves that the secured vWAN core routes traffic through the selected security provider and emits usable operational evidence. It is optional, short-lived, and independently destroyable.

## Separation from the core

The core and test harness use different Terraform roots and separate remote-state keys.

- Core: `infra/terraform`
- Test harness: `infra/terraform/test-harness`
- Core state key: `poc-weu-core.terraform.tfstate`
- Test-harness state key: `poc-weu-test-harness.terraform.tfstate`

The test harness must not manage the core vWAN, virtual hub, Azure Firewall, or firewall policy lifecycle. It discovers the deployed core by declared names and resource group.

## Test topology

The harness creates two isolated spoke VNets and one private Linux probe VM in each spoke.

| Component | Address range | Purpose |
| --- | --- | --- |
| Spoke A | `10.10.0.0/16` | Source workload and client probe |
| Spoke B | `10.20.0.0/16` | Destination workload and server probe |
| Probe subnet A | `10.10.1.0/24` | Private VM subnet |
| Probe subnet B | `10.20.1.0/24` | Private VM subnet |

No public IP address, Bastion host, VPN gateway, ExpressRoute gateway, or custmer workload is created.
## Acceptance evidence

The test run must prove all of the following:

- Both spokes are connected to the declared virtual hub.
- Private traffic is steered through the secured hub by routing intent.
- TCP 8080 from Spoke A to Spoke B is allowed by an explicit test rule.
- A separate, intentional denied flow is blocked.
- Azure Firewall diagnostic logs show the allow and deny decisions.
- Azure activity logs show the relevant deployment and configuration events.
- The evidence package contains timestamps, test inputs, command results, and KQL query output.

## Observability

The harness can create a dedicated Log Analytics workspace for the temporary session or send diagnostics to an approved existing workspace. Azure Firewall resource-specific logs are the default source. Grafana and Palo Alto SCM remain separate presentation and security-provider options; neither is required for the first native Azure Firewall test.

## Lifecycle and cost control

The normal sequence is:

```text
validate and plan → approved apply → test → collect evidence → destroy → confirm empty test state
```

The same pipeline or operator that deploys the test harness must execute cleanup even when verification fails. Retaining the environment requires an explicit, time-bound approval.

## Extensibility
