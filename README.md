# Taipan Azure vWAN Accelerator

Created and maintained by **Mohamed Elrehan** for **Taipan Academy**.

A learning POC that deploys an Azure Virtual WAN secured hub with Azure Firewall,
generates controlled traffic, verifies firewall decisions, and provides a
workbook for visual inspection.

The current version supports a disposable, single-region POC.
It is not a production-ready deployment.

## Start here

Follow the **[Start-to-Finish student guide](docs/POC-START-TO-FINISH.md)** for all steps in one file.

1. Follow the [POC quick-start](docs/POC-QUICKSTART.md).
2. Use the [detailed runbook](docs/POC-RUNBOOK.md) for prerequisites,
   configuration, costs, troubleshooting, and recovery.
3. Review the plan before creating billable Azure resources.
4. Deploy, verify evidence, inspect the workbook, then choose Destroy or Keep.

The quick-start currently assumes a prepared Linux environment and configured
Terraform backends. Fresh-machine setup instructions remain to be completed
and validated.

## What is available now

| Capability | Status |
| --- | --- |
| Single secured vWAN hub, Azure Firewall Standard, policy, and routing intent | Fresh live POC verified |
| Customer-owned Azure Storage Terraform state bootstrap | Bicep compiled and validated |
| Temporary two-spoke test harness and private probe VMs | Live POC verified |
| Private TCP allow/deny and controlled HTTPS egress tests | Live acceptance verified |
| Exact network and application firewall decision checks | Live acceptance verified |
| Shared configurable telemetry polling window | Implemented; successful fresh run verified |
| Workbook in the core resource group with POC evidence tables | Deployed configuration and query evidence verified |
| Keep/Destroy choice after testing and workbook inspection | Fresh lifecycle verified |
| Separate retest and destroy scripts, including explicit `--yes` cleanup | Live workflow verified |
| Cleanup retries for recognized timeout failures | Mocked regression checks passed; normal live cleanup verified |
| Multi-region POC, GitHub Actions, Azure DevOps, and production workflows | Future scope |

The workbook adapts Microsoft's Azure Firewall workbook. Its source,
pinned commit, license, and modifications are recorded in the
[observability directory](infra/terraform/test-harness/observability/SOURCE.md).

## User experience

1. Prepare tools, Azure access, Terraform state, and deployment inputs.
2. Plan and review the intended resources.
3. Deploy the core, then the test harness.
4. Generate traffic and verify matching firewall decisions.
5. Validate the deployed workbook and its POC query results.
6. Inspect both evidence tables in your browser.
7. Choose automatic cleanup or retain the POC.
8. Verify cleanup using Terraform state and Azure inventory.

Retained resources can be retested and destroyed using separate scripts.
Browser rendering and the viewer's access require visual inspection.

## Costs and cleanup

The `--approved-cost-cap-eur` argument records an approved allowance.
**It does not enforce an Azure spending cap.**

Azure charges continue while resources exist, including during deployment,
telemetry waiting, workbook inspection, and retention.

The two telemetry stages share a default 90-minute polling window and finish
early when the required evidence is confirmed. Azure operations add elapsed
time; this is not a maximum deployment duration.

Choosing Destroy starts automatic cleanup. Choosing Keep retains resources.
The script does not schedule expiry or guarantee cleanup after terminal
disconnection or forced termination.

Acceptance PASS and Cleanup PASS are separate outcomes.
If cleanup fails, preserve the recovery records and follow the runbook.

## Validation record

A fresh end-to-end execution on 2026-10-06 using commit `7282ec9` confirmed:

- All four traffic checks and matching firewall decisions.
- Deployed-workbook configuration and both POC evidence queries.
- Visible workbook logs before the cleanup choice.
- Automatic cleanup after choosing Destroy.
- Final result: Acceptance PASS / Cleanup PASS.
- Empty Terraform states and both POC resource groups absent.

Evidence directory: `lifecycle-20261006T163650Z`.

This is evidence of one successful fresh POC execution, not a production
certification or a guarantee that future Azure operations will avoid delays.

## Further reading

- [Original project entry point](docs/START-HERE.md)
- [Customer onboarding](docs/operations/CUSTOMER-ONBOARDING.md)
- [Secured-hub topology](docs/architecture/TOPOLOGY.md)
- [Architecture contract](docs/architecture/ARCHITECTURE-CONTRACT.md)
- [Evidence and acceptance results](docs/testing/EVIDENCE.md)
- [POC and production profiles](config/profiles/PROFILES.md)
- [State bootstrap Bicep](bootstrap/state/bicep/main.bicep)
- [Deployment gate and cost controls](docs/operations/DEPLOYMENT-GATE.md)

Some earlier design documents describe future production and CI/CD workflows.
Use the quick-start and runbook as the current POC execution instructions.
Production execution is disabled in the current visual POC runner.

## Ownership and attribution

- The user owns their Azure subscription, identities, Terraform state,
  deployed resources, and cost decisions.
- Infrastructure reuses Azure Verified Modules; workbook upstream
  attribution and licensing are retained.
- Do not commit Terraform state, plans, credentials, private keys,
  deployment evidence, or environment-specific input files.
- Terraform and Bicep must not manage the same resources in one environment.
