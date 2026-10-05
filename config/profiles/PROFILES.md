# Customer configuration profiles

Customers configure an approved profile; they do not edit Terraform module code.

## Choose a profile

- poc-single-hub.tfvars.example is the time-boxed, single-hub acceptance profile. It is intended to run through the POC lifecycle runner.
- production-single-hub.tfvars.example is the starting profile for a retained production core. It must run through the approved CI/CD workflow and uses Azure Firewall Premium by default.

Copy the selected file to a local path ending in .tfvars. The repository ignores that file so customer-specific names, tags, and addresses cannot be committed accidentally.

## Required customer decisions

| Input | Customer decision |
| --- | --- |
| location | Azure region for the hub. |
| resource_group_name and resource names | Organisation naming standard and environment suffix. |
| hub_address_space | Non-overlapping parent space reserved for virtual-hub allocation. |
| virtual_hub_address_prefix | A non-overlapping prefix inside the parent hub space; /24 is the initial profile. |
| azure_firewall_sku_tier | Standard for POC; Premium is the production profile default. |
| owner and cost_center tags | Accountable service owner and financial allocation. |

## State configuration

State storage is configured separately with bootstrap/state/bicep/main.example.bicepparam.

The customer supplies the state resource group and storage names, trusted public egress CIDRs for a POC or private-endpoint mode for production, and Entra object IDs for the operator and pipeline identity. No access key, SAS token, subscription ID, tenant ID, private key, or password belongs in a profile.

## Before any apply

1. Validate that all CIDRs are approved and non-overlapping with existing networks.
2. Obtain a region-specific Azure cost estimate.
3. Confirm the named owner and cleanup time for a POC.
4. Run terraform plan and approve the exact resource actions.
