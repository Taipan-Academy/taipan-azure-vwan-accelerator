# Install the POC tools on Ubuntu

Created and maintained by Mohamed Elrehan for Taipan Academy.

## Before you start

These are draft setup instructions for a clean Ubuntu 22.04 or 24.04
AMD64 environment. A clean-machine walkthrough remains pending.

Run one command block at a time. Stop and investigate if any command fails.

Use a local Linux machine or VM. Native macOS and PowerShell execution of the
complete POC runner is not covered here. ARM64 users should consult the
official installation instructions for their architecture.

This page installs tools only. It does not create Azure resources.
If your tools are already installed, inspect their versions before changing them.

## 1. Check the operating system

```bash
cat /etc/os-release
dpkg --print-architecture
```

Expected: Ubuntu 22.04 or 24.04 and `amd64` for this guide.

## 2. Install Linux utilities

```bash
sudo apt-get update &&
sudo apt-get install -y \
  git python3 openssh-client curl wget gnupg ca-certificates \
  lsb-release apt-transport-https nano coreutils gawk sed grep
```

Enter your Linux password if sudo asks. Password characters are not displayed.

Expected: installation completes without package errors.
Coreutils supplies utilities including timeout, seq, tee, and sha256sum.

## 3. Add the Microsoft package signing key

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

## 4. Add the Azure CLI repository

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

## 5. Install and check Azure CLI

```bash
sudo apt-get update &&
sudo apt-get install -y azure-cli &&
az version
```

Expected: Azure CLI prints its version information.
The onboarding Bicep parameter-file workflow requires Azure CLI >= 2.53.0.

## 6. Add the HashiCorp package signing key

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

## 7. Add the Terraform repository

```bash
poc_ubuntu_codename="$(lsb_release -cs)"

printf '%s\n' \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $poc_ubuntu_codename main" |
  sudo tee /etc/apt/sources.list.d/hashicorp.list
```

## 8. Install Terraform and verify compatibility

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

## 9. Check all required commands

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

## 10. Continue to Azure preparation

Return to [onboarding](CUSTOMER-ONBOARDING.md) to:
1. Clone the repository.
2. Authenticate and select your subscription.
3. Install the logging extension and Bicep.
4. Prepare state storage and data access.
5. Initialize Terraform.
6. Review matching deployment inputs.
7. Follow the POC quick-start.

Tool installation does not prove Azure permissions, state access,
deployment availability, or acceptance success.

## Official references and validation status

- [Microsoft Azure CLI installation](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt)
- [HashiCorp Terraform installation](https://developer.hashicorp.com/terraform/install)

This document is based on official installation guidance.
It has not yet been executed end to end on a clean student machine.
