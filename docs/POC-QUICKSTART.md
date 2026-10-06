# Azure vWAN POC — Start here

Deploy a small secured network, prove its firewall decisions, inspect the
evidence, and remove the environment.

This is a learning POC, not a production deployment.

## 1. Prepare your environment

Run commands in Bash on a Linux environment.

| Your computer | Execution environment |
| --- | --- |
| Linux | Linux terminal |
| Mac | Linux VM; Mac browser for Azure and the workbook |
| Windows | Ubuntu VM or WSL2; Windows browser for Azure and the workbook |

Our live tests used a Linux VM accessed from a Mac.
Native macOS, PowerShell, and the Windows/WSL2 path have not been validated.

Install Git, Azure CLI, compatible Terraform, Python 3, OpenSSH tools,
and the Linux utilities used by the scripts.

You also need:
- An Azure subscription with suitable deployment and deletion permissions.
- Permission to query Log Analytics and access the workbook.
- Prepared Terraform backends and access to their state storage.

This quick-start is not yet a fresh-machine installation guide.
Complete the preparation instructions in [the runbook](POC-RUNBOOK.md)
before executing the POC.

## 2. Get the repository

For a new checkout:

```bash
git clone https://github.com/Taipan-Academy/taipan-azure-vwan-accelerator.git
cd taipan-azure-vwan-accelerator
```

If you already have the repository, open its existing directory instead.
Do not create another checkout to manage a POC that is already running.

The repository URL will be updated after the planned Elrehan move.

Check the local tools:

```bash
for tool in git az terraform python3 ssh-keygen awk sed grep tee sha256sum timeout seq; do
  command -v "$tool" || break
done
```

Expected: a path for every tool. Resolve missing tools before continuing.

## 3. Sign in and select the subscription

```bash
az login --use-device-code
```

Open the printed address in your browser and enter the current code.
Use the intended Azure account.

```bash
read -r -p "POC subscription ID: " poc_subscription_id
az account set --subscription "$poc_subscription_id"
az account show \
  --query '{Account:user.name,Subscription:name,SubscriptionId:id}' \
  --output table
az group list --output none
```

Expected: your intended account and subscription; the resource-group request
completes without an authentication error.

This does not prove access to every resource or to the Terraform backend.

## 4. Review configuration and initialize Terraform

Follow the runbook's backend initialization and input preparation instructions.

Review:
- `infra/terraform/terraform.tfvars` for core settings.
- `infra/terraform/test-harness/terraform.tfvars.example` for harness settings.

The lifecycle generates the harness's actual `terraform.tfvars`.
Leave its dedicated SSH public-key placeholder for the script to replace.

Names referenced by the harness must match the core configuration.
IP ranges must not overlap, and subnets must fit inside their spoke networks.

Do not change deployment inputs or backend settings while a POC is running.
Recovery scripts check their recorded checksums.

## 5. Plan — no resources created

```bash
bash scripts/run-vwan-lifecycle.sh --mode poc --plan-only
```

Expected:
- Terraform validation succeeds.
- The core plan lists the intended changes.
- Acceptance is `NOT_RUN`.
- Cleanup is `NOT_REQUIRED`.

For the current default configuration, the core plan creates six tracked resources.
The harness plan waits until the core exists.

Plan-only does not prove traffic or logging works.

## 6. Deploy and test — billable resources created

```bash
bash scripts/run-vwan-lifecycle.sh \
  --mode poc \
  --execute \
  --approved-cost-cap-eur 10
```

The EUR 10 argument records approval.
It does not enforce a spending cap or guarantee a total cost.

Keep this terminal open. Do not start another apply or destroy against
the same Terraform states.

Expected progress:
1. Core deployment.
2. Harness and workbook deployment.
3. Four traffic checks.
4. Network and application firewall evidence checks.
5. Deployed-workbook configuration and query checks.
6. Results and the Keep/Destroy prompt.

The telemetry stages share a maximum 90-minute polling window.
They finish early when all required evidence is available.
Azure requests and deployment add elapsed time; this is not a total-runtime limit.

An optional shorter polling window can be selected before execution:

```bash
export TAIPAN_TELEMETRY_WAIT_MINUTES=30
```

Valid values are whole minutes from 1 to 90.
A shorter window may fail before fresh logging is ready.
Use `unset TAIPAN_TELEMETRY_WAIT_MINUTES` to restore the default.

Azure charges continue during deployment, waiting, inspection, and retention.

## 7. Understand success

| Check | Required evidence |
| --- | --- |
| Private TCP 8080 | Expected response and firewall Allow |
| Private TCP 8081 | Failed connection and firewall Deny |
| HTTPS www.example.com | Successful request and firewall Allow |
| HTTPS www.microsoft.com | Failed request and firewall Deny |
| Workbook | Expected deployed definition and both POC queries return recent decisions |

A failed connection alone is not proof of a firewall Deny.

Workbook validation uses events since the test started and within the last hour.
If a long wait makes evidence too old, generate fresh evidence with a retest.

Expected successful output includes:

```text
[WORKBOOK] POC private traffic: recent expected decisions confirmed.
[WORKBOOK] POC Internet traffic: recent expected decisions confirmed.
[WORKBOOK] Configuration and query evidence: PASS.
Acceptance test passed. Report: .../REPORT.md
```

The script verifies backend configuration and query results.
It does not verify browser rendering or another user's portal permissions.

## 8. Inspect before deciding

Open the printed observability URL in your browser.

Alternatively, in Azure Portal:
1. Open the core resource group.
2. Filter for Workbook resources.
3. Open `Taipan vWAN POC - Firewall Observability`.

Review both tables:
- **POC private traffic:** source IP, destination IP, port, protocol, action.
- **POC Internet traffic:** source IP, FQDN, port, protocol, action.

Select the test workspace and use Last hour, then refresh.
Widen the time range when investigating older runs.

Keep the lifecycle terminal open while inspecting.

## 9. Choose Destroy or Keep

The current lifecycle displays:

```text
1. Destroy the POC now
2. Keep the POC for further inspection (Azure charges continue)
Selection [1 or 2]:
```

Enter `1` and press Enter to start cleanup now.

Enter `2` and press Enter to retain the POC and return to the shell.
Save the printed evidence-directory path and Destroy later command.

If acceptance fails, Keep is an investigation choice, not a successful result.
Destroy remains available to stop ongoing resource charges.

## 10. Retest a retained POC

Use the original execution directory, not a nested retest directory:

```bash
read -r -p "Original execution evidence directory: " poc_run
bash scripts/retest-vwan-poc.sh "$poc_run"
```

Expected: fresh traffic, telemetry and workbook checks, and a separate report.
Retest does not deploy or destroy infrastructure.

A successful retest does not rewrite the original failed run.

## 11. Destroy a retained POC

Interactive cleanup:

```bash
read -r -p "Original execution evidence directory: " poc_run
bash scripts/destroy-vwan-poc.sh "$poc_run"
```

Review the plans and type `yes` when Terraform requests confirmation.

Explicit cleanup without confirmation prompts:

```bash
bash scripts/destroy-vwan-poc.sh "$poc_run" --yes
```

This deletes the retained POC. Keep the terminal session open until completion.
The option does not schedule background cleanup or guarantee survival
of a terminal disconnection.

Cleanup removes the harness first, then the disposable core.
Recognized timeout failures are retried up to three total attempts.
Other failures stop cleanup and preserve recovery files.

Do not delete state, input snapshots, or key records to bypass a failed safeguard.

## 12. Verify cleanup

Use your configured names if you changed the defaults:

```bash
for group in rg-taipan-vwan-weu-test rg-taipan-vwan-weu-example; do
  printf '%s exists: ' "$group"
  az group exists \
    --subscription "$poc_subscription_id" \
    --name "$group"
done
```

Expected: `false` for both groups.

The cleanup helper also verifies that each Terraform state is empty.
Review the cleanup result and Azure inventory; acceptance PASS does not mean cleanup PASS.

Evidence remains locally. The live workbook is removed during harness cleanup,
even though it is located in the core resource group.

## Reports and troubleshooting

Save:
- The original execution evidence directory.
- `REPORT.md` for completed acceptance.
- `WORKBOOK-VALIDATION.md` for successful workbook checks.
- `LIFECYCLE-RESULT.md` for the original lifecycle outcome.
- `CLEANUP-RESULT.md` after successful later cleanup.
- Query JSON, stderr, traffic refresh evidence, and cleanup attempt logs.

Use [the detailed runbook](POC-RUNBOOK.md) for troubleshooting and recovery.

## Current validation status

The enhanced retained-POC retest on 2026-10-06 passed traffic, telemetry,
deployed-workbook configuration, and both workbook POC queries.

Nine mocked workbook regression checks passed.

Fresh deployment with the shared telemetry deadline remains to be verified.
Unattended cleanup with --yes completed successfully. Terraform states
were verified empty, and both POC resource groups were confirmed absent.
