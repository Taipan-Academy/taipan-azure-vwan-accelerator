# Azure vWAN POC — VS Code Student Guide

Created and maintained by **Mohamed Elrehan** for **Taipan Academy**.

Start with a new laptop and your own Azure subscription. Prepare Linux,
open the repository in Visual Studio Code, edit the configuration files,
then deploy, test, inspect evidence, and clean up.

## Choose where commands run

| Your setup | VS Code runs on | Azure CLI, Terraform and Bash run on |
| --- | --- | --- |
| Ubuntu desktop 22.04/24.04 AMD64 | The Ubuntu laptop | The same Ubuntu laptop |
| Windows or macOS laptop with an Ubuntu VM | Your laptop, with Remote SSH | The Ubuntu VM through VS Code's remote terminal |

This guide's Linux installation commands target Ubuntu 22.04/24.04 AMD64.
They are not native macOS or PowerShell commands. A Linux server without a
desktop does not need the VS Code desktop application installed on it.
Windows WSL and ARM64 installation are outside this walkthrough.

## The student workflow

1. Prepare Linux tools once: Steps 1–9.
2. Install/open VS Code, clone the repository, and sign in: Step 10.
3. Prepare Azure capabilities and state storage once: Steps 11–14.
4. Edit the configuration files in VS Code: Step 15.
5. Initialize state and review the plan with the launcher: Steps 16–17.
6. Run the tested lifecycle and inspect results: Steps 18–21.
7. Retest if retained, destroy, and verify cleanup: Steps 22–24.

The normal POC workflow is **clone → edit variables → plan → run → inspect
→ keep or destroy**. Supporting scripts orchestrate the Terraform modules,
traffic tests, exact firewall-log checks, workbook validation, and cleanup.
You do not need to edit infrastructure module code.

## Before starting

- Use a dedicated learning subscription or environment you are authorized to use.
- Have sudo access on the Ubuntu machine and Internet access for package installation.
- Have permissions to deploy/delete POC resources and access Terraform state.
- Creating state-storage role assignments requires role-assignment permissions;
  Contributor alone is insufficient. Ask an authorized administrator when needed.
- For Remote SSH, have a reachable Ubuntu host and working SSH credentials first.
- Start this new-environment walkthrough only when no existing POC is running.
- Run one command block at a time. Stop and investigate any failure.

**Costs:** state-storage creation and POC deployment create billable resources.
The EUR 10 approval argument does not enforce a spending cap. State storage
remains after POC cleanup and may continue incurring charges.

| Activity | Effect |
| --- | --- |
| Tool installation | Installs software on the Linux machine |
| Clone and edit | Creates/changes local repository files |
| State bootstrap | Creates retained Azure state-storage resources |
| Prepare-only / plan | Reads Azure and state; creates no Azure resources |
| POC execution | Creates billable Azure network and test resources |
| Destroy | Deletes the dedicated POC resources; retains local evidence |

**Validation:** the underlying full lifecycle passed acceptance, workbook
checks, automatic cleanup, and Azure inventory verification on 2026-10-06.
The launcher's preparation path passed with existing initialized backends.
Its full deployment path, fresh-backend initialization, clean-machine setup,
and this VS Code walkthrough remain unverified end to end.

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

### Step 10 — Open VS Code, clone, and authenticate

#### Install VS Code on your laptop

Download Visual Studio Code from [the official download page](https://code.visualstudio.com/download).
Use the Windows/macOS installer on those laptops. On an Ubuntu desktop,
download the AMD64 .deb package and install it with the graphical installer,
or run this in a local Ubuntu terminal using the actual downloaded file path:

```bash
read -r -p "Downloaded VS Code .deb file path: " vscode_package
sudo apt install "$vscode_package"
```

This installs an editor, not Azure resources. Run VS Code as your normal user,
not with sudo. Follow [Microsoft's Linux instructions](https://code.visualstudio.com/docs/setup/linux)
if installation fails.

#### Choose local Ubuntu or Remote SSH

**Local Ubuntu desktop:** open VS Code, then select Terminal → New Terminal.
Use Bash on this laptop for the remaining commands.

**Windows/macOS with an Ubuntu VM:** install Microsoft's **Remote - SSH**
extension in your laptop's VS Code. From the Command Palette, choose
**Remote-SSH: Connect to Host**, enter your actual `username@hostname`, and
authenticate with your existing SSH credentials. Verify the host fingerprint
before accepting a first connection. Select Linux when asked for the host platform.

Open Terminal → New Terminal in the connected window. Commands now execute
on the Ubuntu VM. Verify this before installing tools or cloning:

```bash
uname -s
hostname
pwd
```

Expected: Linux and the intended machine. If SSH is not yet working, complete
host access setup first using [Microsoft's Remote SSH guide](https://code.visualstudio.com/docs/remote/ssh).
Do not run the Linux preparation commands in a local Windows/macOS terminal.

#### Clone and open the project

In the selected Linux terminal:

```bash
mkdir -p ~/Workspace/Projects
cd ~/Workspace/Projects
git clone https://github.com/Taipan-Academy/taipan-azure-vwan-accelerator.git
cd taipan-azure-vwan-accelerator
```

If this folder already exists, inspect it rather than cloning over existing work.
A public HTTPS clone does not require you to configure a GitHub SSH key.

On a local Ubuntu desktop, open the folder with:

```bash
code .
```

If `code` is unavailable, use File → Open Folder. In a Remote SSH window,
use File → Open Folder to select the cloned folder on the Ubuntu host.
Review the repository before granting Workspace Trust. Reopen the integrated
terminal after opening the folder and confirm it is at the repository root:

```bash
pwd
git status --short --branch
```

The Explorer should show `bootstrap`, `infra`, `scripts`, `tests`, and `docs`.
You may install **HashiCorp Terraform** and **Microsoft Bicep** editor extensions
for highlighting and completion. These do not replace the installed CLI tools.

#### Sign in to your Azure subscription

```bash
az login --use-device-code
```

Open the printed URL and enter the current code in your laptop browser.
Sign in to the account that owns or is authorized for your learning subscription.

```bash
read -r -p "Azure subscription ID: " poc_subscription_id
az account set --subscription "$poc_subscription_id"
az account show \
  --query '{Account:user.name,Subscription:name,SubscriptionId:id,Tenant:tenantId}' \
  --output table
az group list --output none
```

Verify the intended account and subscription before creating resources.
Successful login does not by itself establish resource or role-assignment permissions.

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

In VS Code's Explorer, open `bootstrap/state/bicep/main.local.bicepparam`.
This is your private local storage configuration. Edit it and save with Ctrl+S
(Cmd+S on a macOS laptop).

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

Save the file before running the next deployment command.

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

### Step 15 — Customize your POC in VS Code

Configure before planning or creating POC resources. You can use the matching
example defaults for an isolated lab, or change them to your naming convention.
The launcher does not ask for resource names or network IP ranges.

Create your local core variables file without overwriting existing settings:

```bash
if [[ -e infra/terraform/terraform.tfvars ]]; then
  echo "Existing core inputs found; review instead of overwriting."
else
  (umask 077; cp infra/terraform/terraform.tfvars.example infra/terraform/terraform.tfvars)
fi
```

Open these two files in VS Code's Explorer:

| File | Purpose |
| --- | --- |
| `infra/terraform/terraform.tfvars` | Your private local core settings; ignored by Git |
| `infra/terraform/test-harness/terraform.tfvars.example` | The test settings the lifecycle copies to its generated local file |

The harness example is tracked by Git. Keep personal lab changes local unless
you intentionally maintain your own reviewed fork. Check Source Control before
committing. Do not edit files inside `.terraform/modules`.

#### Core variables

| Variable | Meaning / example | Matching harness field |
| --- | --- | --- |
| `location` | Azure region, e.g. `westeurope` | `location` |
| `resource_group_name` | Core RG, e.g. `rg-alex-vwan-weu-poc` | `core_resource_group_name` |
| `virtual_wan_name` | WAN name, e.g. `vwan-alex-weu-poc` | No repeated reference |
| `virtual_hub_name` | Hub name, e.g. `vhub-alex-weu-poc` | `core_virtual_hub_name` |
| `azure_firewall_name` | Firewall name, e.g. `afw-alex-weu-poc` | `core_azure_firewall_name` |
| `firewall_policy_name` | Policy name, e.g. `afwp-alex-weu-poc` | `core_firewall_policy_name` |
| `hub_address_space` | Module hub address space, default `10.250.0.0/16` | No repeated reference |
| `virtual_hub_address_prefix` | Actual hub prefix, default `10.250.0.0/24` | No repeated reference |
| `azure_firewall_sku_tier` | Keep `Standard` for the verified lesson | None |
| `enable_telemetry` | Keep `false` for the lesson's module telemetry setting | Firewall diagnostics are configured separately by the harness |
| `tags` | Labels such as environment, purpose, owner and cost centre | Harness has its own tags |

Do not interpret `enable_telemetry = false` as disabling the POC firewall logs.
The test harness separately enables diagnostic settings and Log Analytics.
Premium/IDPS testing is not part of this verified lesson.

For example, changing the core `virtual_hub_name` to `vhub-alex-weu-poc`
also requires changing the harness `core_virtual_hub_name` to exactly that value.
Apply all five matching name/region updates in the table before planning.

#### Harness variables

| Variable(s) | What to edit |
| --- | --- |
| `test_resource_group_name` | Dedicated test RG, e.g. `rg-alex-vwan-weu-test`; different from the core and state RGs |
| `log_analytics_workspace_name` | Workspace name, e.g. `log-alex-vwan-weu-test` |
| `spoke_a_name`, `spoke_b_name` | Names of the two test VNets |
| `spoke_a_address_space`, `spoke_b_address_space` | Non-overlapping VNet ranges; defaults `10.10.0.0/16`, `10.20.0.0/16` |
| `spoke_a_subnet_prefix`, `spoke_b_subnet_prefix` | Subnets inside their respective VNets; defaults `10.10.1.0/24`, `10.20.1.0/24` |
| `probe_a_vm_name`, `probe_b_vm_name` | Names of the two private test VMs |
| `probe_vm_size` | Default `Standard_B1s`; changing size affects availability and cost |
| `log_retention_days` | Default `30`; changes may affect charges |
| `tags` | Labels for the temporary test resources |
| `probe_vm_admin_ssh_public_key` | Leave `REPLACE_WITH_A_DEDICATED_TEST_PUBLIC_KEY` unchanged |

Keep the hub prefix within the intended hub address space and keep hub/spoke
ranges non-overlapping. Each spoke subnet must fit inside its own VNet.
Use valid Azure names and confirm region/SKU availability for your subscription.
The scripts discover probe IPs; do not hardcode guessed VM private addresses.

The lifecycle generates the harness's actual `terraform.tfvars` and a dedicated
temporary SSH key. Do not create that generated harness file yourself: the
runner refuses to overwrite one already present.

Save both edited files. Do not change inputs or backend keys while a POC is
running or retained; retest and destroy use its recorded checksums.

**State configuration is separate:** storage inputs belong in the local Bicep
parameter file from Step 12. Backend storage locations and state keys are supplied
in Step 16. They do not belong in the core `terraform.tfvars` file.

### Step 16 — Configure state storage using the launcher

Complete Steps 12–15 first: create your Azure state storage and verify access.
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


## Part 3 — Run, inspect, and clean up

### Step 17 — Plan — no resources created

If you completed guided Step 16, a plan has already been generated.
Review that plan. Run the command below only if you changed configuration
after that plan or followed the manual initialization alternative.


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

Enter the exact names from your core and harness configuration files:

```bash
read -r -p "Core POC resource group: " poc_core_group
read -r -p "Test POC resource group: " poc_test_group
for group in "$poc_test_group" "$poc_core_group"; do
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

This combined guide includes VS Code editing, the existing Linux preparation,
and the tested POC scripts. Clean-machine installation, fresh-backend launcher
initialization, and the complete VS Code walkthrough remain pending live validation.
Changing names, region, ranges or VM sizes is not covered by the recorded default-run validation.

## Official editor references

- [VS Code downloads](https://code.visualstudio.com/download)
- [VS Code installation on Linux](https://code.visualstudio.com/docs/setup/linux)
- [VS Code Remote SSH](https://code.visualstudio.com/docs/remote/ssh)
