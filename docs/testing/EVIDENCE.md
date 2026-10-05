# Evidence and acceptance results

The acceptance harness proves the design without public test VM IP addresses, SSH access, or Bastion.

## What is tested

| Check | Expected result |
| --- | --- |
| Probe A to Probe B TCP 8080 | Allowed |
| Probe A to Probe B TCP 8081 | Denied |
| Probe A to `www.example.com` HTTPS | Allowed |
| Probe A to `www.microsoft.com` HTTPS | Denied |
| Azure Firewall network-rule telemetry | Allow and deny records present |
| Azure Firewall application-rule telemetry | Allow and deny records present |

## Evidence output

The lifecycle runner preserves an artifacts folder containing:

- `REPORT.md` — human-readable acceptance outcome
- Test inputs and private probe IP addresses
- Azure Run Command results
- The KQL queries used for validation
- Raw Log Analytics query responses

The temporary Log Analytics workspace can be destroyed with the test harness because the exported evidence remains outside Azure.

## Reading the result

`REPORT.md` is created only after all traffic checks and matching Firewall log checks pass. A failed run leaves the raw evidence in place for troubleshooting; it does not create a false PASS report.
