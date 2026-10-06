# Taipan vWAN Visual POC — User Guide

Quick-start and video walkthrough: [Start here](POC-QUICKSTART.md).


## Purpose

This POC deploys a secured Azure Virtual WAN environment, generates test traffic,
checks the firewall's decisions, and provides a workbook for visual inspection.

You can inspect the workbook before choosing to destroy or keep the environment.
If you keep it, separate scripts let you retest it or destroy it later.

This is a disposable learning POC. Production execution is not supported by this
version.

## Where to run commands

Run commands in Bash on your Linux VM, inside the repository:

```bash
cd ~/Workspace/Projects/taipan-azure-vwan-accelerator
```

Use your Mac browser to sign in to Azure and view the workbook.
The Mac does not need Terraform to inspect the workbook.

This guide assumes the repository, reviewed configuration, and Terraform
backends have already been prepared. It is not a fresh-machine installation guide.

## What gets deployed

| Component | Purpose |
| --- | --- |
| Virtual WAN and virtual hub | Connect the two spoke networks |
| Azure Firewall Standard and policy | Inspect private and Internet traffic |
| Routing intent | Send private and Internet traffic through the firewall |
| Two spoke networks | Provide isolated test networks |
| Probe A and Probe B VMs | Generate and receive test traffic |
| Temporary acceptance-test rules | Permit the intended test traffic |
| Firewall diagnostic setting | Send logs and metrics to Log Analytics |
| Log Analytics workspace | Store firewall telemetry |
| Azure Monitor workbook | Display firewall activity and POC evidence |

The probe VMs do not require public IP addresses or SSH access for testing.
The scripts use Azure VM Run Command.

The lifecycle generates a dedicated temporary SSH key for the probe deployment.

## Costs

Azure resources incur charges while they exist, including while you inspect
the workbook or keep the POC.

The script requires:

```text
--approved-cost-cap-eur <amount>
```

The amount must be greater than zero and no more than 10 EUR.

Despite the flag's name, it records your approved allowance.
It DOES NOT enforce an Azure spending limit, stop resources at that amount,
or guarantee that the deployment will cost less than the allowance.

Use this workflow only when you understand and accept the charges.
Destroy the POC when finished.

## Before starting

You need:

- Bash on Linux.
- Azure CLI and its log-analytics extension.
- Terraform compatible with the repository's version requirements.
- Python 3, OpenSSH tools, awk, sed, grep, tee, and sha256sum.
- Access to deploy and delete resources in the selected Azure subscription.
- Access to the configured Terraform state backend.
- Permission to query the workspace and open its workbook.

Check the tools:

```bash
for tool in az terraform python3 ssh-keygen awk sed grep tee sha256sum; do
  command -v "$tool" || break
done
az version
terraform version
```

If a tool is missing, install it before continuing.

### Select the correct Azure account

Check the current context:

```bash
az account show \
  --query '{Account:user.name,Subscription:name,SubscriptionId:id,Tenant:tenantId}' \
  --output table
```

If you are signed in with the wrong account:

```bash
az logout
az login --use-device-code
```

Open the address printed by Azure CLI in your Mac browser.
Enter the current code from your terminal and sign in with the intended account.
Use a private browser window if another account is selected automatically.

Select your intended subscription:

```bash
read -r -p "POC subscription ID: " poc_subscription_id
az account set --subscription "$poc_subscription_id"
az account show --output table
az group list --output none
```

A successful account listing alone does not prove all required access.
The resource-group request checks live Azure management access.
Terraform also needs access to its state backend.

If Azure reports that security defaults or an access policy blocked login,
resolve authentication with your tenant administrator. Do not disable security
controls just to run the POC.

### Install the logging extension

```bash
az extension show --name log-analytics
```

If it is missing:

```bash
az extension add --name log-analytics
```

Azure CLI may identify this extension as a preview extension.

The virtual-wan extension is useful for manual hub troubleshooting, but the
lifecycle does not require it for deployment:

```bash
az extension add --name virtual-wan
```

### Check configuration and Terraform initialization

The core input file must exist:

```text
infra/terraform/terraform.tfvars
```

Review its region, resource names, address ranges, tags, and other deployment
settings.

Review:

```text
infra/terraform/test-harness/terraform.tfvars.example
```

Its core resource-group, hub, firewall, and policy names must match the core
configuration.

Do not create the harness terraform.tfvars yourself for a fresh lifecycle run.
The script generates it and inserts the dedicated temporary public key.

Both Terraform directories must already be initialized with their intended
backend configuration. If necessary, initialize them using the repository's
backend setup instructions:

```bash
terraform -chdir=infra/terraform init
terraform -chdir=infra/terraform/test-harness init
```

Do not accept backend migration or reconfiguration prompts without reviewing
which state is being selected.

Validate the configurations:

```bash
terraform -chdir=infra/terraform validate
terraform -chdir=infra/terraform/test-harness validate
```

For a new execution, both states must be empty:

```bash
terraform -chdir=infra/terraform state list
terraform -chdir=infra/terraform/test-harness state list
```

Successful commands with no resource addresses are the expected result.
An authentication error or missing-state error is not confirmation of an empty
state.

If resources are retained from an earlier run, use Retest or Destroy later.
Do not start another lifecycle against those resources.

## Step 1 — Plan without deploying

```bash
bash scripts/run-vwan-lifecycle.sh --mode poc --plan-only
```

The script checks prerequisites, validates Terraform, and saves a core plan.

Expected final output:

```text
Plan-only preflight succeeded. Core plan: .../core.tfplan
No Azure resources were created.
[FINAL] Acceptance: NOT_RUN
[FINAL] Cleanup: NOT_REQUIRED
[FINAL] Result: .../LIFECYCLE-RESULT.md
```

The harness plan intentionally waits until the core exists.
Plan-only does not prove connectivity or observability.

Review the core plan before execution. The current one-hub configuration has
been observed to plan six core resources, but the count depends on configuration.

## Step 2 — Execute the POC

For an approved allowance of 10 EUR:

```bash
bash scripts/run-vwan-lifecycle.sh \
  --mode poc \
  --execute \
  --approved-cost-cap-eur 10
```

Run it in an interactive terminal. Unattended execution is not supported.

The execution creates a new plan and automatically applies the core and harness.
There are no separate Terraform "yes" prompts during these applies.

The workflow is:

1. Check Azure access, prerequisites, and empty POC states.
2. Record the account, backend fingerprints, and recovery information.
3. Validate and plan the core.
4. Generate the temporary key and harness inputs.
5. Format harness inputs before recording their checksums.
6. Apply the secured vWAN core.
7. Plan and apply the harness and workbook.
8. Run traffic tests.
9. Query and validate the exact firewall decisions.
10. Print results, evidence paths, and the observability URL.
11. Wait for your Keep/Destroy selection.

### What to expect while waiting

Terraform prints resource creation progress, including "Still creating..."
messages.

Deployment duration varies. A fixed completion time is not guaranteed.

Acceptance progress includes:

```text
[TEST 1/4] TCP 8080...
[TEST 2/4] TCP 8081...
[TEST 3/4] HTTPS www.example.com:443...
[TEST 4/4] HTTPS www.microsoft.com:443...
[READINESS] Elapsed ...; polling time remaining ...
[TELEMETRY] Network query attempt ...
[TELEMETRY] Application query attempt ...
[WORKBOOK] Configuration and query evidence: PASS.
```

Individual Azure Run Command requests can take time to return.

After the four traffic checks, both telemetry stages share one polling
window, defaulting to 90 minutes. The application stage uses the remaining
time; it does not receive another 90 minutes. Verification finishes early
when all required decisions are confirmed.

Progress shows elapsed and remaining polling time. Unsuccessful queries
normally have 30-second waits. Deployment, traffic checks, Azure requests,
and workbook validation add elapsed time; this is not a total-runtime limit.

An unresolved stage refreshes its two traffic checks at query attempt 2,
then no more often than every five minutes. Refresh results are saved as
traffic-refresh files. Command failure, missing expected traffic results,
or unexpected connectivity stops the test.

Acceptance requires exact firewall Allow/Deny decisions since the current
test started. Background events and events from previous runs cannot
substitute for those decisions.

The polling window can be configured for a command:

```bash
TAIPAN_TELEMETRY_WAIT_MINUTES=30 \
  bash scripts/run-vwan-lifecycle.sh \
  --mode poc --execute --approved-cost-cap-eur 10
```

Valid values are whole minutes from 1 to 90. A shorter window may end before
logging is ready. The same setting applies to the retest script.

Azure charges continue while waiting. Neither this timeout nor the cost
approval argument enforces a spending cap.

The messages about expected blocked connectivity are preliminary traffic
results. Final acceptance additionally requires the matching firewall Deny logs.

Do not start a second Terraform apply or destroy against the same states while
the lifecycle is running.

## What acceptance proves

| Check | Expected result |
| --- | --- |
| Probe A to Probe B TCP 8080 | Allowed; expected response received |
| Probe A to Probe B TCP 8081 | Connection fails; firewall Deny confirmed |
| HTTPS www.example.com:443 | Successful request; firewall Allow confirmed |
| HTTPS www.microsoft.com:443 | Request fails; firewall Deny confirmed |
| Network-rule telemetry | Exact source/destination/port/protocol/action pairs |
| Application-rule telemetry | Exact source/FQDN/port/action pairs |
| Workbook configuration and POC queries | Expected deployed definition and all required recent decisions |

The telemetry queries are restricted to the test start time and discovered
probe IP addresses.

Before writing the acceptance PASS report, the script fetches the deployed
workbook and verifies its definition and source workspace against the expected
configuration. It runs the deployed POC private and Internet table queries
against the test workspace and requires all expected decisions.

These workbook evidence queries additionally require events within the last
hour. A long wait can make earlier evidence too old; in that case, use a retest
to generate fresh evidence rather than treating older rows as a new PASS.

Saved workbook evidence includes:
- workbook-deployed.json and its stderr file.
- workbook-network.kql and workbook-application.kql.
- Query result JSON and stderr for both tables.
- WORKBOOK-VALIDATION.md after successful validation.

These checks verify configuration and backend query results. They do not
verify browser rendering or another viewer's portal permissions. Visually
inspect both POC tables before choosing Keep or Destroy.

A timeout or validation failure remains FAIL. The lifecycle still offers
Keep for investigation or Destroy to remove billable resources.

Successful Terraform deployment alone is not acceptance.
A visible workbook alone is not acceptance.

## Step 3 — Inspect observability BEFORE choosing

At the end of testing, the terminal prints:

```text
POC deployment:      COMPLETE
Acceptance:          PASS
Observability URL:   https://portal.azure.com/...
Evidence directory:  .../artifacts/lifecycle-...
Acceptance report:   .../REPORT.md

1. Destroy the POC now
2. Keep the POC for further inspection (Azure charges continue)
Selection [1 or 2]:
```

Keep the terminal open at this prompt while inspecting the workbook.
No selection is required until you finish inspecting.
Charges continue while the resources are running.

1. Open the printed observability URL on your Mac.
2. Sign in with an Azure account permitted to access this POC.
3. Select the workbook's Overview tab.
4. Select the test workspace if prompted.
5. Set the time range to Last hour and refresh.
6. Find POC Traffic Evidence near the top.

If the URL is lost, open Resource groups, select rg-taipan-vwan-weu-example,
filter by resource type Workbook, and open
Taipan vWAN POC - Firewall Observability.

Retrieve the current URL from the Linux repository with:

    terraform -chdir=infra/terraform/test-harness output -raw observability_url

The workbook lives in the core resource group alongside the hub and firewall.
Logs remain in the test workspace. The harness Terraform state manages the
workbook, including its destruction.

### POC evidence tables

POC private traffic shows:

- TimeGenerated
- SourceIp
- DestinationIp
- DestinationPort
- Protocol
- Action
- ActionReason
- RuleCollection and Rule

POC Internet traffic shows the same core details with Fqdn as the destination.

For the default test networks, expected events are:

| Source | Destination | Port | Action |
| --- | --- | --- | --- |
| 10.10.1.4 | 10.20.1.4 | 8080 | Allow |
| 10.10.1.4 | 10.20.1.4 | 8081 | Deny |
| 10.10.1.4 | www.example.com | 443 | Allow |
| 10.10.1.4 | www.microsoft.com | 443 | Deny |

Actual probe addresses are recorded in test-inputs.json.

The tables show matching traffic for this POC firewall within the selected time
range. They are not restricted to one acceptance run and are not automated PASS
indicators. REPORT.md records the automated acceptance result.

Each table displays up to 2,000 events, newest first. Use the grid's filter/search
controls to inspect specific rows.

Choose a wider time range to inspect older retained events.
The default workspace configuration retains logs for 30 days.

The upstream Network Rules and Application Rules tabs provide additional views.
Some upstream panels depend on optional traffic types or GeoLocation data.
An empty panel does not by itself mean firewall logging is broken.
The added POC evidence tables do not depend on an external GeoLocation lookup.

### Optional AI assistance

If Azure exposes an AI assistant in the workspace's Logs experience, it can
help you find or formulate queries, subject to your account's feature access.

This POC does not deploy a custom AI agent, and its acceptance decisions do not
depend on AI. Logging and the workbook use Azure Monitor and Log Analytics.

## Step 4 — Choose Destroy or Keep

### Option 1 — Destroy now

At Selection [1 or 2], type:

```text
1
```

Press Enter.

The lifecycle automatically attempts to destroy the harness first, then the
core. There are no further Terraform confirmation prompts in this path.

If harness cleanup fails, core cleanup is skipped and recovery inputs are kept.

Expected successful final result:

```text
[FINAL] Acceptance: PASS
[FINAL] Cleanup: PASS
[FINAL] Result: .../LIFECYCLE-RESULT.md
```

Verify Azure inventory afterward as described below.

### Option 2 — Keep

At Selection [1 or 2], type:

```text
2
```

Press Enter.

The script retains the core, probes, rules, workspace, and workbook.
It exits back to your shell; it does not close your terminal application.

Expected final result:

```text
[FINAL] Acceptance: PASS
[FINAL] Cleanup: RETAINED
[OBSERVABILITY] https://portal.azure.com/...
[RETEST] bash .../scripts/retest-vwan-poc.sh .../artifacts/lifecycle-...
[DESTROY LATER] bash .../scripts/destroy-vwan-poc.sh .../artifacts/lifecycle-...
```

Copy the printed commands and retain the original execution evidence path.

Keep the repository at the same path and retain its Terraform backend setup,
core/harness input files, and recovery records. Retest and Destroy check these.

Do not run a new lifecycle while this deployment is retained.

### If acceptance fails

After a completed deployment, acceptance FAIL still offers the inspection and
Keep/Destroy choice.

Review run.log, query stderr files, and probe evidence.
REPORT.md is generated only when all acceptance checks pass.

Keeping a failed acceptance run does not turn it into a passing POC.
The command exits with the acceptance failure status.

## Retest a kept POC

Use the original execution evidence directory, not a plan-only directory or a
retest subdirectory.

Copy the exact RETEST command printed by the lifecycle. Its form is:

```bash
bash scripts/retest-vwan-poc.sh /absolute/path/to/artifacts/lifecycle-RUN_ID
```

The script checks the repository path, subscription, backend fingerprints, and
input checksums. It then repeats acceptance testing.

It does not deploy or destroy resources.

Fresh evidence is saved under:

```text
artifacts/lifecycle-RUN_ID/retest-UTC_TIMESTAMP/
```

Expected successful output includes:

```text
Acceptance test passed. Report: .../retest-.../REPORT.md
Retest report: .../retest-.../REPORT.md
Observability: https://portal.azure.com/...
```

The original lifecycle report remains the record of the original run.

## Destroy a kept POC later

Copy the exact DESTROY LATER command printed by the lifecycle. Its form is:

```bash
bash scripts/destroy-vwan-poc.sh /absolute/path/to/artifacts/lifecycle-RUN_ID
```

This path uses interactive Terraform destruction.

1. Review the harness destroy plan.
2. Type yes and press Enter to remove the harness.
3. Review the core destroy plan.
4. Type yes and press Enter to remove the core.

Normally there are two confirmations. An already-empty state may need no
confirmation.

Both Destroy now and Destroy later use a shared cleanup helper.
Each Terraform destroy allows at most three attempts. Only the recognized
context deadline exceeded error is retried, with a 30-second wait.
Access/authentication errors, state-lock errors, cancellation, and other
unrecognized errors stop cleanup without an automatic retry.

Destroy later is interactive by default: review each displayed plan and type
yes when prompted, including on a retry. Destroy now uses the deletion choice
already made in the lifecycle prompt.

For explicitly approved cleanup without confirmation prompts:

```bash
bash scripts/destroy-vwan-poc.sh \
  /absolute/path/to/artifacts/lifecycle-RUN_ID --yes
```

The --yes option retains repository, subscription, backend, and input checks.
It does not bypass cleanup errors or allow core destruction after harness
cleanup fails.

Keep the terminal session open until completion. No keyboard input is needed
with --yes, but this is not scheduled background cleanup and it does not
guarantee survival of a terminal disconnection.

Each attempt is recorded in a separate cleanup directory under the run's
evidence directory. A successful destroy must also leave an empty Terraform
state. Harness failure prevents core destruction; recovery inputs are retained.
Azure inventory verification remains a separate required check.
After successful destruction, it checks both states are empty, removes the
generated harness input file and dedicated key, and writes CLEANUP-RESULT.md.

Evidence remains on your Linux VM.

Harness destruction removes the test workspace and the workbook located in
the core resource group. Core destruction follows only after harness
destruction succeeds. The observability URL then stops providing a live dashboard.

## Verify cleanup in Azure

Terraform's successful destruction is one check. Verify that both POC resource
groups are absent as well.

For the default configuration:

```bash
for group in rg-taipan-vwan-weu-test rg-taipan-vwan-weu-example; do
  printf '%s exists: ' "$group"
  az group exists --name "$group"
done
```

Run this in the original POC subscription.
If you customized the names, substitute your actual resource-group names.

Expected:

```text
rg-taipan-vwan-weu-test exists: false
rg-taipan-vwan-weu-example exists: false
```

A command error is not proof of absence.

These checks cover the POC groups; they do not claim that unrelated subscription
resources or separate Terraform backend infrastructure were deleted.

## Evidence and final results

Each lifecycle uses a UTC timestamp in its directory name.

| File | Meaning |
| --- | --- |
| azure-context.json | Account and subscription used |
| run.log | Lifecycle console output |
| core.tfplan / harness.tfplan | Saved deployment plans |
| test-inputs.json | Probe addresses and intended flows |
| allowed-flow-attempt-*.json | Allowed private-flow evidence |
| denied-flow.json | Blocked private-flow evidence |
| internet-allowed.json / internet-denied.json | HTTPS test evidence |
| firewall-log-query-attempt-*.json | Network telemetry |
| firewall-application-log-query-attempt-*.json | Application telemetry |
| *.stderr | Log-query errors or diagnostic output |
| REPORT.md | Generated only after all acceptance checks pass |
| LIFECYCLE-RESULT.md | Original acceptance, cleanup, and exit status |
| CLEANUP-RESULT.md | Successful later-destroy result |
| backend-checksums.txt / input-checksums.txt | Recovery fingerprints |
| core-inputs.tfvars / harness-inputs.tfvars | Recorded deployment inputs |

Acceptance and cleanup are separate outcomes:

- PASS / RETAINED: tests passed; resources remain chargeable.
- PASS / PASS: tests passed; cleanup commands succeeded; verify inventory.
- FAIL / PASS: acceptance failed; cleanup commands succeeded.
- NOT_RUN: acceptance was not reached.
- Cleanup FAIL: review recovery information; resources may remain.

Keep local artifacts, plans, input snapshots, keys, and debug logs private.
Commit source and documentation, not the artifacts directory or private input
files.

## Troubleshooting

### Existing resources or harness inputs

A fresh execution refuses existing tracked resources or an existing harness
terraform.tfvars.

Use the original Retest/Destroy commands for a retained run.
Do not delete recovery inputs just to bypass the check.

### Input checksum mismatch

Retest and Destroy refuse changed recorded inputs.

Compare the current file with its saved snapshot.
Do not blindly regenerate checksums.

The lifecycle now formats the generated harness inputs before recording them.
Later intentional edits can still cause a mismatch and require review.

### Workbook lowercase validation

The workbook source_id is normalized with lower() in Terraform.
This fixes the observed AzureRM lowercase validation error.

### Logs have not arrived

Allow automatic queries and bounded traffic refreshes to finish.
Initial traffic may precede logging readiness. The cause of the observed
initial missing events has not been established.

Inspect query, traffic-refresh, and stderr evidence if acceptance fails.
Retesting a retained POC generates fresh traffic and a separate report.
A successful retest does not overwrite the original failed result.

A query failure is different from a successful query missing the expected rows.
The verifier rejects malformed results and unexpected query errors.

### Virtual hub appears ready but Terraform keeps waiting

One test run showed Azure reporting Succeeded/Provisioned while Terraform's
routing-state wait eventually timed out. This was not reproduced on retry.
The cause has not been established.

Use another terminal for read-only Azure checks.
Do not run another apply against the locked state.

You can inspect the hub with:

```bash
az network vhub show \
  --resource-group rg-taipan-vwan-weu-example \
  --name vhub-taipan-weu-example \
  --query '{ProvisioningState:provisioningState,RoutingState:routingState}' \
  --output json
```

Substitute your configured names when different.

A ready snapshot alone does not establish why Terraform is waiting.
Keep the failure output and review the lifecycle's cleanup result.

### Failure or interruption before the final choice

Earlier execution failures and handled Ctrl+C/SIGTERM attempt automatic cleanup.

A terminal disconnection or forced process termination does not guarantee cleanup.
Reconnect and inspect the recorded run, state, and Azure inventory.

If cleanup fails, retain the recovery files and review the printed Destroy later
command. Very early failures may occur before complete recovery records exist;
inspect the actual run files before using recovery scripts.

## Reuse and validation status

Infrastructure uses the Azure Verified Module vWAN pattern.
The workbook is adapted from Microsoft's Azure-Network-Security repository;
its source, pinned commit, license, and local changes are recorded in the
observability directory.

Public vWAN labs are references for explanations and troubleshooting.
This project makes no claim that its architecture or workflow is unique.

On 2026-10-05, the following were verified:

- All six acceptance checks passed.
- The POC workbook evidence tables were visually confirmed.
- Retest passed and saved separate evidence.
- Later Destroy succeeded.
- Both POC resource groups were confirmed absent.
- Bash syntax, Terraform validation, and Git whitespace checks passed.

On 2026-10-06, fresh deployment reached the Keep/Destroy prompt. Four traffic
checks passed, but network telemetry was empty through 20 attempts. Initial
acceptance remained FAIL. The POC was retained and a separate retest passed.

The traffic-refresh change passed five local helper checks and a live retest.
Application refresh ran at attempt 2; exact decisions were confirmed at
attempt 4. The workbook was moved into the core resource group and visually
verified. Backend and input checksum checks passed during retest.

Cleanup with the relocated workbook completed on 2026-10-06. Azure inventory
confirmed both POC resource groups were absent; local evidence was retained.

A subsequent fresh run, lifecycle-20261006T110850Z, passed all six acceptance
checks using bounded traffic refreshes. Both evidence tables were visually
confirmed in the workbook in the core resource group before choosing Destroy.

Initial automatic cleanup failed while reading Probe B's OS disk, with
context deadline exceeded. The core and inputs were retained. The later-destroy
recovery succeeded, and Azure inventory confirmed both resource groups absent.
The original lifecycle result remains Acceptance PASS / Cleanup FAIL;
the later cleanup result is separate. The underlying timeout cause is unknown.

The shared cleanup-retry helper subsequently passed Bash syntax checks and
nine simulated tests: immediate success, timeout recovery, retry exhaustion,
access error, unknown error, cancellation, interruption, state-read failure,
and non-empty state. No Azure calls were made by these simulated tests.

A later fresh run, lifecycle-20261006T134452Z, passed all four traffic
checks but did not confirm network telemetry within the original 20 attempts.
Its original acceptance result remains FAIL. Fresh firewall events became
visible later. The precise cause of the initial missing evidence is unconfirmed.

The verifier was enhanced with a shared configurable telemetry polling
deadline and deployed-workbook validation. Bash syntax and six timeout
configuration checks passed. Nine mocked workbook checks passed, covering
success, missing network/application evidence, incorrect workspace/workbook
identity, changed definition, API failure, malformed rows, and incorrect GUID.

The enhanced retained-POC retest, retest-20261006T153547Z, passed all traffic
and telemetry checks. Network telemetry passed at query 1; application
telemetry passed at query 4. Both deployed workbook POC queries and the
configuration check passed. The script completed early rather than waiting
the full 90 minutes.

The explicit --yes later-destroy workflow completed successfully.
The cleanup helper confirmed empty Terraform states, and Azure inventory
confirmed both POC resource groups were absent. Evidence was retained.

Pending:
Fresh full-lifecycle validation completed on 2026-10-06 using commit
7282ec9, run lifecycle-20261006T163650Z.

- All four traffic checks passed.
- Network telemetry passed at query 1.
- Application telemetry passed at query 4 after a traffic refresh.
- Deployed-workbook configuration and both POC query checks passed.
- The user confirmed logs were visible before choosing Destroy.
- Choosing 1 triggered automatic cleanup without further confirmation.
- Final lifecycle result: Acceptance PASS / Cleanup PASS.
- Terraform cleanup verified empty states.
- Azure inventory confirmed both POC resource groups absent.

This verifies one successful fresh execution. It does not establish production
readiness or guarantee future Azure operations will avoid delays or failures.
- Complete and validate fresh-machine setup instructions.
- Review documentation and branding before release.

This guide describes an interactive Linux workflow with workbook access from
a Mac browser. AWS/GCP deployments, production execution, and custom AI agents
are outside this POC's scope.
