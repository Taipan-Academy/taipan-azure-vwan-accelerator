# Start Here

Use this page as the front door to the accelerator.

## Choose your route

| Route | Use it when | Outcome |
| --- | --- | --- |
| POC | You need proof before committing to production | Deploy, test, export evidence, then remove all POC resources |
| Production | You have approved design, ownership, funding, and change control | Retain the secured vWAN core and remove only the temporary test harness |

## The guided path

1. Read the [topology](architecture/TOPOLOGY.md) and confirm it fits the intended use.
2. Create or select customer-owned Terraform state using the [onboarding guide](operations/CUSTOMER-ONBOARDING.md).
3. Copy the approved [POC or production profile](../config/profiles/PROFILES.md).
4. Run the lifecycle runner in plan-only mode and review the exact result.
5. Obtain cost and change approval.
6. Execute the approved path.
7. Read the exported [evidence report](testing/EVIDENCE.md).

## What the first profile includes

- One Standard Azure Virtual WAN and one virtual hub
- Azure Firewall Standard or Premium and Firewall Policy
- Routing intent for private and Internet traffic
- Optional isolated acceptance test: two spoke VNets and two private probe VMs
- Azure Run Command tests, Log Analytics evidence, and `REPORT.md`

It intentionally excludes VPN, ExpressRoute, Point-to-Site VPN, Bastion, workload resources, customer data, and DDoS Network Protection.

## Before any deploy

- Confirm non-overlapping IP ranges with the network authority.
- Confirm region availability and a current cost estimate.
- Record the service owner, cost centre, environment, and POC cleanup time.
- Use only the customer subscription and customer-owned state account.

## Need more detail?

- [Customer inputs](../config/profiles/PROFILES.md)
- [Architecture scope](architecture/FIRST-PROFILE-SCOPE-MATRIX.md)
- [Deployment gate](operations/DEPLOYMENT-GATE.md)
- [Test harness contract](architecture/TEST-HARNESS-CONTRACT.md)
