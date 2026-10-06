# Prepare the Azure POC environment

This guide prepares customer-owned Terraform state and matching POC inputs.
It does not claim production readiness or completed fresh-machine validation.

## 1. Execution environment and tools

For copyable installation commands, follow [Ubuntu setup](UBUNTU-SETUP.md) first.


The verified workflow runs in Bash on Linux, accessed from a Mac.
For the beginner path, use an Ubuntu VM on your own computer.

Native macOS, PowerShell, and Windows/WSL2 execution have not been validated.
Azure-hosted control VMs need a separately reviewed storage-network path.

Install Git, Azure CLI, Terraform, Python 3, OpenSSH tools, and Linux utilities.

Official installation references:
- [Azure CLI on Linux](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt)
- [Terraform installation](https://developer.hashicorp.com/terraform/install)

The repository requires Terraform >= 1.9.0 and < 2.0.0.
Check the installed version against `infra/terraform/versions.tf`.

```bash
for tool in git az terraform python3 ssh-keygen awk sed grep tee sha256sum timeout seq; do
  command -v "$tool" || break
done
az version
terraform version
```

Expected: every tool is found. Stop if any is missing.

## 2. Clone and authenticate

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

## 3. Prepare Azure CLI capabilities

```bash
az extension add --name log-analytics
az bicep install
az bicep version
```

The log-analytics extension may be a preview version.
If Bicep is already installed, inspect its version before updating it.

Using `.bicepparam` directly requires Azure CLI >= 2.53.0 and a compatible
Bicep CLI; Microsoft's deployment guidance specifies Bicep >= 0.22.6.

## 4. Prepare state bootstrap inputs

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

## 5. Review and deploy the state bootstrap

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

## 6. Verify state data access

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

## 7. Initialize separate Terraform states

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

## 8. Prepare matching POC settings

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

## 9. Plan, deploy, inspect, and destroy

Continue with [the quick-start](../POC-QUICKSTART.md) and
[the detailed runbook](../POC-RUNBOOK.md).

The current lifecycle:
- Plans before applying.
- Requires explicit cost approval, not an enforced spending cap.
- Deploys the core and harness.
- Verifies traffic, firewall telemetry, and workbook evidence.
- Offers Destroy or Keep after inspection.
- Provides separate retest and destroy scripts.

Production execution and CI/CD provisioning are not implemented in this version.

## 10. Understand what cleanup retains

POC cleanup removes the test harness and disposable vWAN core.
It retains local evidence and the separately bootstrapped Terraform-state storage.

That storage may incur charges even when both POC resource groups are absent.
Review it separately. Do not delete shared state storage, or delete any backend
while it is still needed for active resources, recovery, or audit records.

## Validation status

The POC lifecycle was verified in a prepared environment.
These corrected onboarding instructions are based on the repository templates
and official deployment guidance. A clean-machine walkthrough remains pending.

References:
- [Bicep CLI deployment](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/deploy-cli)
- [Storage firewall limitations](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security-limitations)
