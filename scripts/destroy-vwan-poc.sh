#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 1 ]]; then
  echo "Usage: destroy-vwan-poc.sh <execution-evidence-directory>" >&2
  exit 64
fi

run="$(cd "$1" && pwd)"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$(cat "$run/repository-path.txt")" == "$root" ]] || {
  echo "Run belongs to a different repository path. Review before recovery."
  exit 1
}

expected_subscription="$(cat "$run/subscription-id.txt")"
actual_subscription="$(az account show --query id --output tsv)"
[[ "$actual_subscription" == "$expected_subscription" ]] || {
  echo "Wrong subscription. Select the run's subscription first:"
  printf 'az account set --subscription %q\n' "$expected_subscription"
  exit 1
}

export ARM_SUBSCRIPTION_ID="$expected_subscription"
export ARM_TENANT_ID="$(az account show --query tenantId --output tsv)"

sha256sum --check "$run/backend-checksums.txt"
sha256sum --check "$run/input-checksums.txt"

echo
echo "POC subscription: $expected_subscription"
echo "Run evidence:     $run"
echo "Order: test harness first, then disposable vWAN core."
echo "Terraform will display the resources in each destroy plan."

# Interactive destroy: review Terraform's targets and type yes.
terraform -chdir="$root/infra/terraform/test-harness" destroy
terraform -chdir="$root/infra/terraform" destroy

for directory in \
  "$root/infra/terraform/test-harness" \
  "$root/infra/terraform"; do
  remaining="$(terraform -chdir="$directory" state list)"
  [[ -z "$remaining" ]] || {
    echo "Cleanup incomplete: resources still tracked in $directory"
    exit 1
  }
done

key_path="$(cat "$run/key-path.txt")"
case "$key_path" in
  "$root"/artifacts/keys/taipan-vwan-acceptance-*)
    rm -f "$key_path" "$key_path.pub"
    ;;
  *)
    echo "Unexpected key path; leaving key files untouched."
    ;;
esac

rm -f "$root/infra/terraform/test-harness/terraform.tfvars"
{
  echo "# Later cleanup result"
  echo
  echo "Terraform destroy commands: PASS"
  echo "Both Terraform states: empty"
  echo "Verify Azure inventory separately for untracked resources."
} >"$run/CLEANUP-RESULT.md"

echo "Tracked POC resources destroyed."
echo "Evidence retained: $run"
echo "Azure inventory verification is still required."
