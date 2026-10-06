# Azure vWAN POC — Start to Finish

Created and maintained by **Mohamed Elrehan** for **Taipan Academy**.

This is the main student and video guide. Follow the steps in order.
It includes the commands for tool installation, Azure preparation,
Terraform initialization, deployment, verification, and cleanup.

This guide covers one-time preparation and the complete POC workflow.
Once tools and state storage are ready, the guided launcher simplifies
account selection, backend initialization, input checks, planning, and execution.

## Guided route after one-time preparation

Run from the repository directory with no existing POC running.

First, prepare and review the plan:

```bash
bash scripts/start-poc.sh --prepare-only
```

This checks tools, guides Azure account and subscription selection, reuses
existing state storage, initializes separate backends, requires empty POC
states, checks matching inputs, and runs plan-only. It creates no Azure resources.

When ready to deploy:

```bash
bash scripts/start-poc.sh
```

Review the account, subscription, backend locations, inputs, and plan.
Type DEPLOY only when ready to create billable POC resources with the
displayed EUR 10 allowance. That allowance does not enforce a spending cap.

The existing lifecycle then deploys, tests traffic, verifies firewall logs
and workbook query evidence, and offers Destroy or Keep. Inspect the workbook
before choosing. After destruction, verify both POC resource groups are absent.

The launcher does not install tools or create state storage.
Complete the preparation steps below if those are not ready.
For custom names or IP ranges, prepare matching core and harness inputs first.

**Validation:** the launcher's preparation path passed against existing
initialized backends on 2026-10-06. Its guided deployment path has not yet
been verified live. The underlying full POC lifecycle has passed separately.

## Before following this guide

- Use a dedicated learning environment and an Azure subscription you control.
- Installation instructions target Ubuntu 22.04/24.04 AMD64.
- You need sudo access on Linux.
- Azure deployment requires suitable resource permissions.
- State bootstrap role assignments require role-assignment permissions;
  have an authorized administrator perform that step if necessary.
- Stop if a command fails; do not continue blindly.
- Follow this new-environment guide only when no existing POC is running.

**Cost notice:** POC resources are billable. The cost approval argument does
not enforce a spending cap. Separately created Terraform-state storage
remains after POC cleanup and may continue incurring charges.

A fresh POC lifecycle passed deployment, acceptance, workbook checks, and
automatic cleanup. These complete clean-machine setup instructions have
not yet been verified end to end.

## How to use the guide

Run commands in the Linux terminal. Use your browser for Azure login
and workbook inspection. Run one command block at a time.

The installation commands install software on the machine.
The state bootstrap and POC execution commands create Azure resources.
Plan-only does not create POC resources. Destroy commands delete them.


## Part 1 — Install the tools

### Before you start

These are draft setup instructions for a clean Ubuntu 22.04 or 24.04
AMD64 environment. A clean-machine walkthrough remains pending.

Run one command block at a time. Stop and investigate if any command fails.

Use a local Linux machine or VM. Native macOS and PowerShell execution of the
complete POC runner is not covered here. ARM64 users should consult the
official installation instructions for their architecture.

This page installs tools only. It does not create Azure resources.
If your tools are already installed, inspect their versions before changing them.

### Step 1 — Check the operating system

```bash
cat /etc/os-release
dpkg --print-architecture
```

Expected: Ubuntu 22.04 or 24.04 and `amd64` for this guide.

### Step 2 — Install Linux utilities

```bash
sudo apt-get update &&
sudo apt-get install -y \
  git python3 openssh-client curl wget gnupg ca-certificates \
  lsb-release apt-transport-https nano coreutils gawk sed grep
```

Enter your Linux password if sudo asks. Password characters are not displayed.

Expected: installation completes without package errors.
Coreutils supplies utilities including timeout, seq, tee, and sha256sum.

### Step 3 — Add the Microsoft package signing key

```bash
sudo mkdir -p /etc/apt/keyrings
```

```bash
(
  set -o pipefail
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc |
    gpg --dearmor |
    sudo tee /etc/apt/keyrings/microsoft.gpg >/dev/null
) &&
sudo chmod go+r /etc/apt/keyrings/microsoft.gpg
```

Expected: successful completion; little or no output.

### Step 4 — Add the Azure CLI repository

```bash
poc_ubuntu_codename="$(lsb_release -cs)"

printf '%s\n' \
  "Types: deb" \
  "URIs: https://packages.microsoft.com/repos/azure-cli/" \
  "Suites: $poc_ubuntu_codename" \
  "Components: main" \
  "Architectures: $(dpkg --print-architecture)" \
  "Signed-by: /etc/apt/keyrings/microsoft.gpg" |
  sudo tee /etc/apt/sources.list.d/azure-cli.sources
```

Expected: the repository definition is printed with jammy or noble.

### Step 5 — Install and check Azure CLI

```bash
sudo apt-get update &&
sudo apt-get install -y azure-cli &&
az version
```

Expected: Azure CLI prints its version information.
The onboarding Bicep parameter-file workflow requires Azure CLI >= 2.53.0.

### Step 6 — Add the HashiCorp package signing key

```bash
(
  set -o pipefail
  curl -fsSL https://apt.releases.hashicorp.com/gpg |
    gpg --dearmor |
    sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null
) &&
sudo chmod go+r /usr/share/keyrings/hashicorp-archive-keyring.gpg
```

Expected: successful completion.

### Step 7 — Add the Terraform repository

```bash
poc_ubuntu_codename="$(lsb_release -cs)"

printf '%s\n' \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $poc_ubuntu_codename main" |
  sudo tee /etc/apt/sources.list.d/hashicorp.list
```

### Step 8 — Install Terraform and verify compatibility

```bash
sudo apt-get update &&
sudo apt-get install -y terraform &&
terraform version
```

The repository requires Terraform >= 1.9.0 and < 2.0.0.
Check that requirement explicitly:

```bash
python3 - <<'CHECK'
import json
import subprocess

result = subprocess.run(
    ["terraform", "version", "-json"],
    check=True, capture_output=True, text=True,
)
version = json.loads(result.stdout)["terraform_version"]
parts = tuple(int(part) for part in version.split("-")[0].split(".")[:3])
if not ((1, 9, 0) <= parts < (2, 0, 0)):
    raise SystemExit("Unsupported Terraform version: " + version)
print("Terraform version is compatible:", version)
CHECK
```

Expected: `Terraform version is compatible`.

Package repositories change over time. If the installed version is outside
the repository's range, stop and install a compatible version using the
official Terraform instructions. Do not bypass the version constraint.

### Step 9 — Check all required commands

```bash
python3 - <<'CHECK'
import shutil

tools = [
    "git", "az", "terraform", "python3", "ssh-keygen",
    "awk", "sed", "grep", "tee", "sha256sum", "timeout", "seq",
]
missing = []
for tool in tools:
    path = shutil.which(tool)
    print(tool + ": " + (path or "MISSING"))
    if not path:
        missing.append(tool)
if missing:
    raise SystemExit("Install missing tools: " + ", ".join(missing))
print("All required commands are available.")
CHECK
```

Expected: every command is found.

## Part 2 — Prepare Azure and Terraform

### Step 10 — Clone and authenticate

For a new checkout:

```bash
git clone https://github.com/Taipan-Academy/taipan-azure-vwan-accelerator.git
cd taipan-azure-vwan-accelerator
az login --use-device-code
```

Open the printed URL and enter the current code in your browser.

```bash
read -r -p "Azure subscription ID: " poc_subscription_id
az account set --subscription "$poc_subscription_id"
az account show \
  --query '{Account:user.name,Subscription:name,SubscriptionId:id,Tenant:tenantId}' \
  --output table
az group list --output none
```

Verify the intended account and subscription.

The operator needs permission to deploy/delete POC resources and permission
to deploy the subscription-scoped state bootstrap.

Creating the bootstrap's role assignments additionally requires appropriate
role-assignment permissions. Contributor alone does not grant that capability.
Have an authorized administrator perform the bootstrap when needed.

### Step 11 — Prepare Azure CLI capabilities

```bash
az extension add --name log-analytics
az bicep install
az bicep version
```

The log-analytics extension may be a preview version.
If Bicep is already installed, inspect its version before updating it.

Using `.bicepparam` directly requires Azure CLI >= 2.53.0 and a compatible
Bicep CLI; Microsoft's deployment guidance specifies Bicep >= 0.22.6.

### Step 12 — Prepare state bootstrap inputs

The bootstrap creates a dedicated resource group, storage account,
private blob container, and optional operator/pipeline role assignments.

It disables shared keys and anonymous blob access, enables blob versioning
and retention, and restricts network access.

Create the local parameter file only if it does not already exist:

```bash
if [[ -e bootstrap/state/bicep/main.local.bicepparam ]]; then
  echo "Existing local parameters found; review them instead of overwriting."
else
  cp bootstrap/state/bicep/main.example.bicepparam \
    bootstrap/state/bicep/main.local.bicepparam
fi
```

Obtain your signed-in user object ID:

```bash
az ad signed-in-user show --query id --output tsv
```

If directory access prevents this lookup, ask the administrator for the
correct user object ID. Do not substitute a subscription ID or application ID.

Edit the local file:

```bash
nano bootstrap/state/bicep/main.local.bicepparam
```

Replace:
- `location`: approved state-storage region.
- `stateResourceGroupName`: dedicated state resource group.
- `storageAccountName`: globally unique, 3–24 lowercase letters/digits.
- `allowedPublicIpCidrs`: the actual public IPv4 egress address/range
  of the machine running Terraform.
- `operatorPrincipalId`: your Entra user object ID.

Leave `pipelinePrincipalId` empty for this local POC.
Use `publicNetworkAccess = 'Enabled'` for this IP-restricted beginner path.

The example `203.0.113.0/24` and all-zero object ID are placeholders.
Do not deploy them unchanged.

In nano: Ctrl+O, Enter saves; Ctrl+X exits.

Storage IP rules do not allow clients merely because they are Azure VMs.
Clients in the same Azure region require an appropriate VNet/service-endpoint
or private-endpoint design. The trusted-services bypass is not a blanket
exception for arbitrary VMs.

Do not disable storage network restrictions or enable shared keys to bypass
an access failure.

### Step 13 — Review and deploy the state bootstrap

This step creates resources that remain outside POC cleanup.

First inspect the proposed deployment:

```bash
az deployment sub what-if \
  --name taipan-tfstate-bootstrap \
  --location westeurope \
  --parameters bootstrap/state/bicep/main.local.bicepparam
```

Use the appropriate deployment location if required by your environment.
Review the resource group, storage account, container, and role assignments.

Then deploy:

```bash
az deployment sub create \
  --name taipan-tfstate-bootstrap \
  --location westeurope \
  --parameters bootstrap/state/bicep/main.local.bicepparam
```

The parameter file's `using './main.bicep'` selects the template.
Do not prefix a `.bicepparam` path with `@`.

Inspect the backend outputs:

```bash
az deployment sub show \
  --name taipan-tfstate-bootstrap \
  --query properties.outputs \
  --output json
```

Expected: resource group, storage account, container, and Azure AD auth outputs.

### Step 14 — Verify state data access

Enter the values from those outputs:

```bash
read -r -p "State resource group: " state_resource_group
read -r -p "State storage account: " state_storage_account
read -r -p "State container: " state_container

az storage container show \
  --account-name "$state_storage_account" \
  --name "$state_container" \
  --auth-mode login \
  --output json
```

Expected: the container can be read without shared keys.

New role assignments can take time to become effective.
An access failure may be caused by identity permissions or network restrictions.
Resolve it before initialization; do not repeatedly deploy the POC.

If you open a new terminal, re-enter the subscription and backend variables.

### Step 15 — Configure state storage using the launcher

Complete Steps 12–14 first: create your Azure state storage and verify access.
Use this step only when no existing POC is running.

**Recommended student route:** run the guided launcher from the repository:

```bash
bash scripts/start-poc.sh --prepare-only
```

Confirm your Azure account and subscription.

On a new checkout, enter the storage names from the Bicep deployment outputs:

| Prompt | What to enter |
| --- | --- |
| State resource group | Your state-storage resource-group name |
| State storage account | Your storage-account name |
| State container [tfstate] | Press Enter if your container is named tfstate |
| Dedicated state key prefix [poc/weu] | Press Enter for an isolated default lab, or use a distinct prefix for another environment |

The launcher displays two separate state keys:

```text
poc/weu/vwan-core.tfstate
poc/weu/vwan-acceptance-test.tfstate
```

Review the storage destination and keys, then enter y to confirm.
Do not use another student's state keys.

If both backends are already initialized, the launcher instead displays their
existing storage configuration and asks whether to reuse it.

The launcher initializes both backends, requires empty POC states, prepares
default core inputs when absent, checks matching core/harness names and region,
and runs the plan-only workflow.

Expected final message:

```text
[PREPARED] Setup and plan completed. No vWAN POC deployed.
```

This command creates no Azure resources. State storage from Step 13 remains.
Stop and investigate if any check fails.

**Do not also run the manual initialization commands below.**
They are an alternative reference, not an additional student step.

<details>
<summary>Alternative: manual Terraform initialization</summary>

These commands are for a new checkout with no existing deployment.
Do not point them at another user's live state.

```bash
export ARM_SUBSCRIPTION_ID="$(az account show --query id --output tsv)"
export ARM_TENANT_ID="$(az account show --query tenantId --output tsv)"

terraform -chdir=infra/terraform init \
  -backend-config="resource_group_name=$state_resource_group" \
  -backend-config="storage_account_name=$state_storage_account" \
  -backend-config="container_name=$state_container" \
  -backend-config="key=poc/weu/vwan-core.tfstate" \
  -backend-config="use_cli=true" \
  -backend-config="use_azuread_auth=true"

terraform -chdir=infra/terraform/test-harness init \
  -backend-config="resource_group_name=$state_resource_group" \
  -backend-config="storage_account_name=$state_storage_account" \
  -backend-config="container_name=$state_container" \
  -backend-config="key=poc/weu/vwan-acceptance-test.tfstate" \
  -backend-config="use_cli=true" \
  -backend-config="use_azuread_auth=true"
```

Expected: both initializations succeed.

Use dedicated state keys for each separate POC environment.
Do not run concurrent executions against the same core or harness state.
For an existing backend, follow reviewed migration/reconfiguration guidance
rather than blindly overwriting its settings.

</details>

### Step 16 — Prepare matching POC settings

```bash
if [[ -e infra/terraform/terraform.tfvars ]]; then
  echo "Existing core inputs found; review instead of overwriting."
else
  cp infra/terraform/terraform.tfvars.example \
    infra/terraform/terraform.tfvars
fi
```

The core Taipan defaults match
`infra/terraform/test-harness/terraform.tfvars.example`.

If you change core names or region, update the harness's core references
and region accordingly. Keep hub/spoke ranges non-overlapping and place each
subnet inside its spoke address space.

The lifecycle generates the actual harness `terraform.tfvars` and a dedicated
temporary SSH key. Leave the public-key placeholder in the harness example.

Do not commit local parameters, inputs, state, plans, or keys.

## Part 3 — Run, inspect, and clean up

### Step 17 — Plan — no resources created

If you completed the guided Step 15, a plan has already been generated.
Review that plan. Run the command below only if you changed inputs in Step 16
or followed the manual initialization alternative.


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

### Step 18 — Deploy and test — billable resources created

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

### Step 19 — Understand success

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

### Step 20 — Inspect before deciding

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

### Step 21 — Choose Destroy or Keep

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

### Step 22 — Retest a retained POC

Use the original execution directory, not a nested retest directory:

```bash
read -r -p "Original execution evidence directory: " poc_run
bash scripts/retest-vwan-poc.sh "$poc_run"
```

Expected: fresh traffic, telemetry and workbook checks, and a separate report.
Retest does not deploy or destroy infrastructure.

A successful retest does not rewrite the original failed run.

### Step 23 — Destroy a retained POC

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

### Step 24 — Verify cleanup

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

## Completion checklist

- Traffic tests and exact firewall decisions passed.
- Workbook configuration and both POC queries passed.
- Both POC tables were inspected in the browser.
- Cleanup completed successfully.
- Both POC resource groups were confirmed absent.
- Local evidence was retained.
- State storage was reviewed separately; it is not removed by POC cleanup.

## Detailed references

- [Quick-start](POC-QUICKSTART.md)
- [Troubleshooting and recovery](POC-RUNBOOK.md)
- [Onboarding](operations/CUSTOMER-ONBOARDING.md)
- [Ubuntu installation](operations/UBUNTU-SETUP.md)

## Validation status

The prepared-environment POC lifecycle was verified on 2026-10-06:
Acceptance PASS, Cleanup PASS, and both POC resource groups absent.

This combined guide consolidates the existing instructions.
Clean-machine installation and onboarding validation remain pending.
