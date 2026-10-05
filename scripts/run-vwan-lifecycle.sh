#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  run-vwan-lifecycle.sh --mode poc|production --plan-only
  run-vwan-lifecycle.sh --mode poc|production --execute --approved-cost-cap-eur <amount>

The core is deployed first. Only after its apply succeeds does the script create
the isolated test harness, run evidence verification, and start cleanup.

Safety controls:
  - --plan-only creates no Azure resources.
  - --execute requires an approved cost cap of 10 EUR or less.
  - poc mode destroys test and core resources on exit.
  - production mode destroys only temporary test resources on exit.
USAGE
}

mode=""
action="plan-only"
approved_cost_cap_eur=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) mode="${2:-}"; shift 2 ;;
    --plan-only) action="plan-only"; shift ;;
    --execute) action="execute"; shift ;;
    --approved-cost-cap-eur) approved_cost_cap_eur="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done

if [[ "$mode" != "poc" && "$mode" != "production" ]]; then
  echo "Specify --mode poc or --mode production." >&2
  exit 64
fi

if [[ "$action" == "execute" ]]; then
  if [[ ! "$approved_cost_cap_eur" =~ ^[0-9]+([.][0-9]{1,2})?$ ]] || ! awk "BEGIN { exit !($approved_cost_cap_eur > 0 && $approved_cost_cap_eur <= 10) }"; then
    echo "Execution requires --approved-cost-cap-eur with a value greater than 0 and no more than 10." >&2
    exit 64
  fi
fi

for required_command in az terraform ssh-keygen awk sed; do
  command -v "$required_command" >/dev/null || {
    echo "Required command is unavailable: $required_command" >&2
    exit 127
  }
done

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
core_directory="$repository_root/infra/terraform"
harness_directory="$repository_root/infra/terraform/test-harness"
core_tfvars="$core_directory/terraform.tfvars"
harness_tfvars="$harness_directory/terraform.tfvars"
harness_example="$harness_directory/terraform.tfvars.example"
verifier="$repository_root/scripts/run-vwan-acceptance-test.sh"
run_id="$(date -u +%Y%m%dT%H%M%SZ)"
evidence_directory="$repository_root/artifacts/lifecycle-$run_id"
key_directory="$repository_root/artifacts/keys"
key_path="$key_directory/taipan-vwan-acceptance-$run_id"
core_applied=false
harness_applied=false

if [[ ! -f "$core_tfvars" ]]; then
  echo "Missing reviewed local core input file: $core_tfvars" >&2
  exit 1
fi

if [[ ! -f "$harness_example" || ! -x "$verifier" ]]; then
  echo "The test harness or verifier is incomplete. Restore the repository baseline before running." >&2
  exit 1
fi

mkdir -p "$evidence_directory"
az account show --query "{subscription:name,subscriptionId:id,user:user.name,state:state}" --output json >"$evidence_directory/azure-context.json"

cleanup() {
  result=$?
  trap - EXIT INT TERM

  if [[ "$action" == "execute" ]]; then
    if [[ "$harness_applied" == true ]]; then
      echo "Cleaning up temporary acceptance-test resources..."
      terraform -chdir="$harness_directory" destroy -auto-approve || true
    fi

    if [[ "$mode" == "poc" && "$core_applied" == true ]]; then
      echo "Cleaning up POC core resources..."
      terraform -chdir="$core_directory" destroy -auto-approve || true
    fi

    rm -f "$harness_tfvars" "$key_path" "$key_path.pub"
  fi

  exit "$result"
}

trap cleanup EXIT INT TERM

terraform -chdir="$core_directory" validate
terraform -chdir="$harness_directory" validate
terraform -chdir="$core_directory" plan -out="$evidence_directory/core.tfplan"

if [[ "$action" == "plan-only" ]]; then
  printf 'Plan-only preflight succeeded. Core plan: %s/core.tfplan\n' "$evidence_directory"
  printf 'No Azure resources were created. The harness plan intentionally waits for the core to exist.\n'
  exit 0
fi

if [[ -e "$harness_tfvars" ]]; then
  echo "Refusing to overwrite existing local test input file: $harness_tfvars" >&2
  exit 1
fi

umask 077
mkdir -p "$key_directory"
ssh-keygen -q -t ed25519 -N "" -C "taipan-vwan-acceptance-$run_id" -f "$key_path"
cp "$harness_example" "$harness_tfvars"
public_key_escaped="$(sed 's/[\/&]/\\&/g' "$key_path.pub")"
sed -i "s/REPLACE_WITH_A_DEDICATED_TEST_PUBLIC_KEY/$public_key_escaped/" "$harness_tfvars"

printf 'Applying secured vWAN core with approved cost cap EUR %s...\n' "$approved_cost_cap_eur"
core_applied=true
terraform -chdir="$core_directory" apply -auto-approve "$evidence_directory/core.tfplan"

printf 'Planning and applying the isolated acceptance-test harness...\n'
terraform -chdir="$harness_directory" plan -out="$evidence_directory/harness.tfplan"
harness_applied=true
terraform -chdir="$harness_directory" apply -auto-approve "$evidence_directory/harness.tfplan"

test_resource_group="$(terraform -chdir="$harness_directory" output -raw test_resource_group_name)"
workspace_id="$(terraform -chdir="$harness_directory" output -raw log_analytics_workspace_id)"
probe_a_vm_name="$(awk -F'"' '/^probe_a_vm_name[[:space:]]*=/{print $2}' "$harness_tfvars")"
probe_b_vm_name="$(awk -F'"' '/^probe_b_vm_name[[:space:]]*=/{print $2}' "$harness_tfvars")"

if [[ -z "$probe_a_vm_name" || -z "$probe_b_vm_name" ]]; then
  echo "Unable to determine probe VM names from the generated local test inputs." >&2
  exit 1
fi

"$verifier" "$test_resource_group" "$probe_a_vm_name" "$probe_b_vm_name" "$workspace_id" "$evidence_directory"
printf 'Lifecycle succeeded. Acceptance evidence: %s/REPORT.md\n' "$evidence_directory"
