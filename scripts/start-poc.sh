#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'HELP'
Usage:
  bash scripts/start-poc.sh
  bash scripts/start-poc.sh --prepare-only

Guided POC launcher for Linux with tools installed and existing state storage.
--prepare-only prepares configuration and runs plan-only; it does not deploy
the vWAN POC. Existing state storage may already incur charges.

New state-storage creation and automatic tool installation are not included yet.
HELP
}

prepare_only=false
case "${1:-}" in
  "") [[ $# == 0 ]] || { usage >&2; exit 64; } ;;
  --prepare-only)
    [[ $# == 1 ]] || { usage >&2; exit 64; }
    prepare_only=true
    ;;
  --help|-h) usage; exit 0 ;;
  *) usage >&2; exit 64 ;;
esac

[[ "$(uname -s)" == Linux ]] || {
  echo "Use Bash in the supported Linux environment." >&2
  exit 1
}
[[ -t 0 ]] || {
  echo "This guided launcher requires an interactive terminal." >&2
  exit 1
}

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

for tool in az terraform python3 ssh-keygen awk sed grep tee sha256sum timeout seq; do
  command -v "$tool" >/dev/null || {
    echo "Missing tool: $tool"
    echo "Follow docs/operations/UBUNTU-SETUP.md, then run this launcher again."
    exit 127
  }
done

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
    raise SystemExit("Terraform must be >= 1.9.0 and < 2.0.0: " + version)
print("[TOOLS] Terraform compatible:", version)
CHECK

core="$root/infra/terraform"
harness="$core/test-harness"

[[ ! -e "$harness/terraform.tfvars" ]] || {
  echo "Existing harness inputs found. Use Retest or Destroy for that run."
  echo "Do not overwrite inputs to start another POC."
  exit 1
}

echo
echo "[ACCOUNT] Current Azure session:"
if ! az account show \
  --query '{User:user.name,Subscription:name,SubscriptionId:id}' \
  --output table; then
  echo "No usable session. Starting device-code login."
  az login --use-device-code --output none
else
  read -r -p "Use this signed-in account? [y/N]: " answer
  if [[ "$answer" != y && "$answer" != Y ]]; then
    az login --use-device-code --output none
  fi
fi

az account list \
  --query '[].{Name:name,SubscriptionId:id,User:user.name}' \
  --output table

read -r -p "Subscription ID to use: " subscription
[[ "$subscription" =~ ^[0-9a-fA-F-]{36}$ ]] || {
  echo "Enter a subscription GUID." >&2
  exit 64
}
az account set --subscription "$subscription"
az account show \
  --query '{User:user.name,Subscription:name,SubscriptionId:id}' \
  --output table

read -r -p "Confirm this subscription [y/N]: " answer
[[ "$answer" == y || "$answer" == Y ]] || exit 0

export ARM_SUBSCRIPTION_ID="$(az account show --query id --output tsv)"
export ARM_TENANT_ID="$(az account show --query tenantId --output tsv)"
az group list --output none

if ! az extension show --name log-analytics >/dev/null 2>&1; then
  echo "[TOOLS] Installing the Azure CLI log-analytics extension."
  az extension add --name log-analytics
fi

core_metadata="$core/.terraform/terraform.tfstate"
harness_metadata="$harness/.terraform/terraform.tfstate"

if [[ -e "$core_metadata" || -e "$harness_metadata" ]]; then
  [[ -f "$core_metadata" && -f "$harness_metadata" ]] || {
    echo "Only one backend is initialized. Complete onboarding before continuing."
    exit 1
  }

  echo "[STATE] Checking the existing backend configuration."
  python3 - "$core_metadata" "$harness_metadata" <<'CHECK'
import json
import sys

configs = []
for path in sys.argv[1:]:
    backend = json.load(open(path))["backend"]
    if backend["type"] != "azurerm":
        raise SystemExit("Expected an Azure Storage backend.")
    config = backend["config"]
    if not config.get("use_azuread_auth") or not config.get("use_cli"):
        raise SystemExit("Expected Azure AD authentication using Azure CLI.")
    configs.append(config)

for key in ("resource_group_name", "storage_account_name", "container_name"):
    if not configs[0].get(key) or configs[0][key] != configs[1].get(key):
        raise SystemExit("Backend destinations differ; review before continuing.")
    print(key + ": " + str(configs[0][key]))

if not all(config.get("key") for config in configs):
    raise SystemExit("Missing state key.")
if configs[0]["key"] == configs[1]["key"]:
    raise SystemExit("Core and harness must use different state keys.")

for label, config in zip(("Core state key", "Harness state key"), configs):
    print(label + ": " + config["key"])
CHECK

  read -r -p "Use these existing backends? [y/N]: " answer
  [[ "$answer" == y || "$answer" == Y ]] || exit 0

  terraform -chdir="$core" init -input=false
  terraform -chdir="$harness" init -input=false
else
  echo "[STATE] Enter an existing state account you are authorized to use."
  echo "To create one first, follow docs/operations/CUSTOMER-ONBOARDING.md."

  read -r -p "State resource group: " state_group
  read -r -p "State storage account: " state_account
  read -r -p "State container [tfstate]: " state_container
  state_container="${state_container:-tfstate}"
  read -r -p "Dedicated state key prefix [poc/weu]: " state_prefix
  state_prefix="${state_prefix:-poc/weu}"

  [[ "$state_account" =~ ^[a-z0-9]{3,24}$ ]] || {
    echo "Invalid storage account name." >&2
    exit 64
  }
  [[ -n "$state_group" && -n "$state_container" ]] || exit 64
  [[ "$state_prefix" =~ ^[a-zA-Z0-9][a-zA-Z0-9/_-]*$ ]] || {
    echo "Invalid state prefix." >&2
    exit 64
  }

  echo "State: $state_group / $state_account / $state_container"
  echo "Core key: $state_prefix/vwan-core.tfstate"
  echo "Harness key: $state_prefix/vwan-acceptance-test.tfstate"
  read -r -p "Confirm these dedicated POC state locations [y/N]: " answer
  [[ "$answer" == y || "$answer" == Y ]] || exit 0

  az storage account show \
    --subscription "$subscription" \
    --resource-group "$state_group" \
    --name "$state_account" \
    --output none
  az storage container show \
    --account-name "$state_account" \
    --name "$state_container" \
    --auth-mode login \
    --output none

  for directory in "$core" "$harness"; do
    key="$state_prefix/vwan-core.tfstate"
    [[ "$directory" != "$harness" ]] ||
      key="$state_prefix/vwan-acceptance-test.tfstate"

    terraform -chdir="$directory" init -input=false \
      -backend-config="resource_group_name=$state_group" \
      -backend-config="storage_account_name=$state_account" \
      -backend-config="container_name=$state_container" \
      -backend-config="key=$key" \
      -backend-config="subscription_id=$ARM_SUBSCRIPTION_ID" \
      -backend-config="tenant_id=$ARM_TENANT_ID" \
      -backend-config="use_cli=true" \
      -backend-config="use_azuread_auth=true"
  done
fi

echo "[STATE] Requiring empty POC states."
for directory in "$core" "$harness"; do
  remaining="$(terraform -chdir="$directory" state list)"
  [[ -z "$remaining" ]] || {
    echo "Existing tracked resources in $directory."
    echo "Use the original run's recovery instructions; do not start a new POC."
    exit 1
  }
done

if [[ ! -e "$core/terraform.tfvars" ]]; then
  umask 077
  cp "$core/terraform.tfvars.example" "$core/terraform.tfvars"
  echo "[INPUTS] Created local core inputs from matching Taipan defaults."
else
  echo "[INPUTS] Preserving existing local core inputs."
fi

python3 - "$core/terraform.tfvars" "$harness/terraform.tfvars.example" <<'CHECK'
import re
import sys
from pathlib import Path

def value(text, key):
    match = re.search(
        r'^\s*' + re.escape(key) + r'\s*=\s*"([^"]+)"',
        text, re.MULTILINE,
    )
    if not match:
        raise SystemExit("Cannot read literal input: " + key)
    return match.group(1)

core, harness = [Path(path).read_text() for path in sys.argv[1:]]
for key, reference in (
    ("location", "location"),
    ("resource_group_name", "core_resource_group_name"),
    ("virtual_hub_name", "core_virtual_hub_name"),
    ("azure_firewall_name", "core_azure_firewall_name"),
    ("firewall_policy_name", "core_firewall_policy_name"),
):
    actual = value(core, key)
    if actual != value(harness, reference):
        raise SystemExit("Core/harness mismatch: " + key + ". Review inputs.")
    print("[INPUTS] " + key + ": " + actual)
CHECK

echo "[PLAN] Running the existing plan-only workflow."
bash "$root/scripts/run-vwan-lifecycle.sh" --mode poc --plan-only

if [[ "$prepare_only" == true ]]; then
  echo "[PREPARED] Setup and plan completed. No vWAN POC deployed."
  exit 0
fi

echo
echo "Review the plan above."
echo "Execution creates billable resources. EUR 10 is approval, not a spending cap."
echo "Resources continue costing money during waiting, inspection, or retention."
echo "The final workflow offers Destroy or Keep."
read -r -p "Type DEPLOY to approve POC execution with a EUR 10 allowance: " answer
[[ "$answer" == DEPLOY ]] || {
  echo "No POC execution requested. State storage remains."
  exit 0
}

exec bash "$root/scripts/run-vwan-lifecycle.sh" \
  --mode poc --execute --approved-cost-cap-eur 10
