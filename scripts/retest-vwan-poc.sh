#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 1 ]]; then
  echo "Usage: retest-vwan-poc.sh <original-execution-evidence-directory>" >&2
  exit 64
fi

run="$(cd "$1" && pwd)"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[[ "$(cat "$run/repository-path.txt")" == "$root" ]] || {
  echo "Run belongs to a different repository path."
  exit 1
}

subscription="$(cat "$run/subscription-id.txt")"
[[ "$(az account show --query id --output tsv)" == "$subscription" ]] || {
  echo "Select the original POC subscription before retesting."
  printf 'az account set --subscription %q\n' "$subscription"
  exit 1
}

export ARM_SUBSCRIPTION_ID="$subscription"
export ARM_TENANT_ID="$(az account show --query tenantId --output tsv)"

sha256sum --check "$run/backend-checksums.txt"
sha256sum --check "$run/input-checksums.txt"
az extension show --name log-analytics >/dev/null

harness="$root/infra/terraform/test-harness"
group="$(terraform -chdir="$harness" output -raw test_resource_group_name)"
workspace="$(terraform -chdir="$harness" output -raw log_analytics_workspace_guid)"
probe_a="$(python3 - "$run/test-inputs.json" <<'INPUT'
import json, sys
print(json.load(open(sys.argv[1]))["probe_a_vm"])
INPUT
)"
probe_b="$(python3 - "$run/test-inputs.json" <<'INPUT'
import json, sys
print(json.load(open(sys.argv[1]))["probe_b_vm"])
INPUT
)"

evidence="$run/retest-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -m 700 "$evidence"
exec > >(tee -a "$evidence/run.log") 2>&1

echo "Retesting retained POC; no deployment or cleanup will run."
bash "$root/scripts/run-vwan-acceptance-test.sh" \
  "$group" "$probe_a" "$probe_b" "$workspace" "$evidence"

echo "Retest report: $evidence/REPORT.md"
echo "Observability: $(terraform -chdir="$harness" output -raw observability_url)"
