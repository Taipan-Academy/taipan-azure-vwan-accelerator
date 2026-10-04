# First secured vWAN deployment gate

This gate applies before deploying the Taipan single-region secured vWAN profile to any Azure subscription. A successful Terraform plan does not grant approval to create billable Azure resources.

## What this profile creates

- One resource group, Standard Virtual WAN, and virtual hub
- One Standard Azure Firewall Policy and secured-hub Azure Firewall
- One routing intent for private and internet traffic

The profile does not create VPN, ExpressRoute, Point-to-Site VPN, Bastion, workload virtual networks, DDoS Network Protection, or customer data resources.

## Cost decision

Obtain a current region-specific estimate in the Azure Pricing Calculator before approving an apply. Include the Standard virtual hub hourly charge, Azure Firewall Standard hourly charge, firewall data processing, hub routing and data-processing charges, and expected data transfer.

Azure Firewall and the Standard virtual hub continue to incur charges while deployed. Name a POC owner and cleanup time before deployment.

## Approval record

Record the target subscription name, region, current estimate, maximum approved POC spend, deployment owner, cleanup deadline, and named approver in a pull request, issue, or change record. Never commit subscription IDs, Terraform state, plans, or credentials.

## Deployment and evidence

After approval, deploy only the reviewed saved plan:

```bash
terraform -chdir=infra/terraform apply taipan-single-hub.tfplan
```

Capture the apply output, routing-intent status, firewall provisioning state, and policy association as evidence.

## Cleanup

For this isolated profile, remove only Terraform-managed resources:

```bash
