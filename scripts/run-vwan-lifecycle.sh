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
  - POC execution offers Destroy or Keep after acceptance checks.
  - Earlier failures or interruption attempt automatic cleanup.
  - Keeping retains the core, probes, workspace and workbook.
  - The cost argument records approval; it does not limit Azure spending.
  - Visual execution requires an interactive terminal and empty POC states.
  - Production execution is unavailable in this visual POC version.
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
source "$script_directory/lib/terraform-cleanup.sh"
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
generated_inputs=false
keep_resources=false
acceptance_status="NOT_RUN"
cleanup_status="NOT_REQUIRED"
observability_url="Not available"
# TAIPAN_VISUAL_POC_V1

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
  set +e

  if [[ "$action" == "execute" ]]; then
    if [[ "$keep_resources" == true ]]; then
      cleanup_status="RETAINED"
      echo "[KEEP] Resources retained. Azure charges continue."
    else
      cleanup_status="PASS"

      if [[ "$harness_applied" == true ]]; then
        echo "[CLEANUP] Removing POC harness..."
        if ! terraform_destroy_with_retry "$harness_directory" "$evidence_directory" harness -auto-approve; then
          cleanup_status="FAIL"
        fi
      fi

      if [[ "$mode" == "poc" && "$core_applied" == true ]]; then
        if [[ "$cleanup_status" == "PASS" ]]; then
          echo "[CLEANUP] Removing POC core..."
          if ! terraform_destroy_with_retry "$core_directory" "$evidence_directory" core -auto-approve; then
            cleanup_status="FAIL"
          fi
        else
          echo "[RECOVERY] Core retained because harness cleanup failed."
        fi
      fi

      if [[ "$cleanup_status" == "PASS" && "$generated_inputs" == true ]]; then
        rm -f "$harness_tfvars" "$key_path" "$key_path.pub"
      fi
      if [[ "$cleanup_status" == "FAIL" ]]; then
        result=1
        echo "[RECOVERY] Inputs retained. Review cleanup errors."
      fi
    fi
  fi

  {
    echo "# POC lifecycle result"
    echo
    echo "- Acceptance: $acceptance_status"
    echo "- Cleanup: $cleanup_status"
    echo "- Exit code: $result"
    echo "- Observability URL: $observability_url"
    echo "- Evidence directory: $evidence_directory"
    echo
    echo "Acceptance PASS does not mean cleanup PASS."
    echo "Verify Terraform state and Azure inventory after destruction."
  } >"$evidence_directory/LIFECYCLE-RESULT.md"

  echo
  echo "[FINAL] Acceptance: $acceptance_status"
  echo "[FINAL] Cleanup: $cleanup_status"
  echo "[FINAL] Result: $evidence_directory/LIFECYCLE-RESULT.md"

  if [[ "$cleanup_status" == "RETAINED" ]]; then
    echo "[OBSERVABILITY] $observability_url"
    printf '[RETEST] bash %q %q\n' \
      "$repository_root/scripts/retest-vwan-poc.sh" "$evidence_directory"
  fi
  if [[ "$cleanup_status" == "RETAINED" || "$cleanup_status" == "FAIL" ]]; then
    printf '[DESTROY LATER] bash %q %q\n' \
      "$repository_root/scripts/destroy-vwan-poc.sh" "$evidence_directory"
  fi
  exit "$result"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

chmod 700 "$evidence_directory"

for tool in python3 grep tee sha256sum; do
  command -v "$tool" >/dev/null || {
    echo "Required command missing: $tool" >&2
    exit 127
  }
done

exec > >(tee -a "$evidence_directory/run.log") 2>&1

echo "[PREFLIGHT] Checking extension and Azure access..."
az extension show --name log-analytics >/dev/null || {
  echo "Run: az extension add --name log-analytics"
  exit 1
}
az group list --output none

for query_file in \
  "$repository_root/tests/integration/kql/firewall-acceptance.kql" \
  "$repository_root/tests/integration/kql/firewall-internet-egress.kql"; do
  [[ -s "$query_file" ]] || {
    echo "Missing query template: $query_file" >&2
    exit 1
  }
done

if [[ "$action" == "execute" ]]; then
  # This visual workflow is limited to the disposable POC.
  [[ "$mode" == "poc" ]] || {
    echo "Visual execution supports POC mode only."
    exit 1
  }
  [[ -t 0 ]] || {
    echo "Interactive terminal required for the final Keep/Destroy choice."
    echo "Unattended execution is not supported by this version."
    exit 1
  }
  [[ ! -e "$harness_tfvars" ]] || {
    echo "Existing harness inputs require review: $harness_tfvars"
    exit 1
  }

  echo "[PREFLIGHT] Checking that both POC states are empty..."
  for directory in "$core_directory" "$harness_directory"; do
    state_resources="$(terraform -chdir="$directory" state list)"
    [[ -z "$state_resources" ]] || {
      echo "Existing tracked resources in $directory. Review before a new run."
      exit 1
    }
  done

  run_subscription="$(az account show --query id --output tsv)"
  run_tenant="$(az account show --query tenantId --output tsv)"
  export ARM_SUBSCRIPTION_ID="$run_subscription"
  export ARM_TENANT_ID="$run_tenant"

  # Reviewable recovery record. Contains local inputs: keep private.
  printf '%s\n' "$run_subscription" >"$evidence_directory/subscription-id.txt"
  printf '%s\n' "$repository_root" >"$evidence_directory/repository-path.txt"
  cp "$core_tfvars" "$evidence_directory/core-inputs.tfvars"

  # Fingerprint backend metadata without copying its contents.
  for directory in "$core_directory" "$harness_directory"; do
    metadata="$directory/.terraform/terraform.tfstate"
    [[ -f "$metadata" ]] || {
      echo "Initialized backend metadata missing: $metadata"
      exit 1
    }
  done

  sha256sum \
    "$core_directory/.terraform/terraform.tfstate" \
    "$harness_directory/.terraform/terraform.tfstate" \
    >"$evidence_directory/backend-checksums.txt"
fi

echo "[PLAN] Validating and planning the core..."


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
generated_inputs=true
public_key_escaped="$(sed 's/[\/&]/\\&/g' "$key_path.pub")"
sed -i "s/REPLACE_WITH_A_DEDICATED_TEST_PUBLIC_KEY/$public_key_escaped/" "$harness_tfvars"
echo "[INPUTS] Formatting generated harness inputs before recording checksums..."
terraform -chdir="$harness_directory" fmt terraform.tfvars
cp "$harness_tfvars" "$evidence_directory/harness-inputs.tfvars"
sha256sum "$core_tfvars" "$harness_tfvars" >"$evidence_directory/input-checksums.txt"
printf '%s\n' "$key_path" >"$evidence_directory/key-path.txt"

printf 'Applying secured vWAN core. Approved allowance EUR %s; spending is not capped...\n' "$approved_cost_cap_eur"
core_applied=true
terraform -chdir="$core_directory" apply -auto-approve "$evidence_directory/core.tfplan"

printf 'Planning and applying the isolated acceptance-test harness...\n'
terraform -chdir="$harness_directory" plan -out="$evidence_directory/harness.tfplan"
harness_applied=true
terraform -chdir="$harness_directory" apply -auto-approve "$evidence_directory/harness.tfplan"

test_resource_group="$(terraform -chdir="$harness_directory" output -raw test_resource_group_name)"
workspace_id="$(terraform -chdir="$harness_directory" output -raw log_analytics_workspace_guid)"
probe_a_vm_name="$(awk -F'"' '/^probe_a_vm_name[[:space:]]*=/{print $2}' "$harness_tfvars")"
probe_b_vm_name="$(awk -F'"' '/^probe_b_vm_name[[:space:]]*=/{print $2}' "$harness_tfvars")"

if [[ -z "$probe_a_vm_name" || -z "$probe_b_vm_name" ]]; then
  echo "Unable to determine probe VM names from the generated local test inputs." >&2
  exit 1
fi

observability_url="$(terraform -chdir="$harness_directory" output -raw observability_url)"
terraform -chdir="$harness_directory" output -json >"$evidence_directory/harness-outputs.json"

echo "[TEST] Running acceptance checks..."
acceptance_exit=0
"$verifier" "$test_resource_group" "$probe_a_vm_name" "$probe_b_vm_name" "$workspace_id" "$evidence_directory" || acceptance_exit=$?

if [[ "$acceptance_exit" == 0 ]]; then
  acceptance_status="PASS"
else
  acceptance_status="FAIL"
fi

echo
echo "POC deployment:      COMPLETE"
echo "Acceptance:          $acceptance_status"
echo "Observability URL:   $observability_url"
echo "Evidence directory:  $evidence_directory"
if [[ "$acceptance_status" == "PASS" ]]; then
  echo "Acceptance report:   $evidence_directory/REPORT.md"
else
  echo "Review run.log and evidence JSON files for the failure."
fi
echo
echo "Open the URL on your Mac and sign in with the POC Azure account."
echo "Workbook access still depends on Azure permissions."
echo "An available workbook is not itself proof that all tests passed."
echo
echo "1. Destroy the POC now"
echo "2. Keep the POC for further inspection (Azure charges continue)"

while true; do
  if ! read -r -p "Selection [1 or 2]: " selection; then
    echo "No selection received; cleanup will be attempted."
    exit 1
  fi
  case "$selection" in
    1) keep_resources=false; break ;;
    2) keep_resources=true; break ;;
    *) echo "Enter 1 to destroy or 2 to keep." ;;
  esac
done

exit "$acceptance_exit"
