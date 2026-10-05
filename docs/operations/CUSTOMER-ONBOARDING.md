# Customer onboarding

This guide keeps customer infrastructure, Terraform state, identities, and evidence in the customer tenant.

## 1. Clone and review

Clone the repository into the customer's GitHub or Azure DevOps organisation. Review the architecture contract, cost gate, and selected configuration profile before creating resources.

## 2. Bootstrap customer-owned Terraform state

The state bootstrap uses Bicep because Terraform cannot safely use a backend that it has not created yet.

1. Copy `bootstrap/state/bicep/main.example.bicepparam` to `bootstrap/state/bicep/main.local.bicepparam`.
2. Replace the example names, trusted public IP CIDRs, and Entra object IDs.
3. For a production private-endpoint design, set `publicNetworkAccess` to `Disabled` only after private connectivity and private DNS are ready.
4. Compile and deploy the bootstrap:

```bash
az bicep build --file bootstrap/state/bicep/main.bicep
az deployment sub create \
  --name taipan-tfstate-bootstrap \
  --location westeurope \
  --template-file bootstrap/state/bicep/main.bicep \
  --parameters @bootstrap/state/bicep/main.local.bicepparam
```

The operator and CI/CD workload identity require the Storage Blob Data Contributor role on the state storage account. Do not enable shared keys, create SAS tokens, or store credentials in the repository.

## 3. Initialise the separate state files

Create separate state files for the core and temporary acceptance harness. Substitute the values from the Bicep deployment outputs.

```bash
terraform -chdir=infra/terraform init -reconfigure \
  -backend-config="resource_group_name=<state-resource-group>" \
  -backend-config="storage_account_name=<state-storage-account>" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=poc/weu/vwan-core.tfstate" \
  -backend-config="use_cli=true" \
  -backend-config="use_azuread_auth=true"

terraform -chdir=infra/terraform/test-harness init -reconfigure \
  -backend-config="resource_group_name=<state-resource-group>" \
  -backend-config="storage_account_name=<state-storage-account>" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=poc/weu/vwan-acceptance-test.tfstate" \
  -backend-config="use_cli=true" \
  -backend-config="use_azuread_auth=true"
```

## 4. Select an architecture profile

Copy either `config/profiles/poc-single-hub.tfvars.example` or `config/profiles/production-single-hub.tfvars.example` to `infra/terraform/terraform.tfvars`.

Set the customer naming standard, approved CIDRs, owner, cost centre, Firewall tier, and environment tags. The copied file is ignored by Git.

## 5. Plan before change

```bash
scripts/run-vwan-lifecycle.sh --mode poc --plan-only
```

Review the exact Terraform plan, Azure cost estimate, named owner, and planned cleanup time.

## 6. POC lifecycle

The POC runner deploys the core first, then the temporary test harness, collects evidence, and automatically destroys both. It requires an explicit cost cap:

```bash
scripts/run-vwan-lifecycle.sh \
  --mode poc \
  --execute \
  --approved-cost-cap-eur 10
```

The evidence folder contains `REPORT.md`, raw Azure Run Command results, and Log Analytics query results. It remains local after cloud cleanup.

## 7. Production lifecycle

Production uses the approved CI/CD workflow with OpenID Connect or workload identity federation. The production core is retained; only the temporary acceptance harness is removed after testing. Do not use personal access tokens, client secrets, or storage keys.

## Support boundaries

Taipan supplies the architecture, templates, validation, and evidence format. The customer owns the Azure subscription, Microsoft Entra identities, Terraform state account, approval process, deployed resources, and operational decisions.
