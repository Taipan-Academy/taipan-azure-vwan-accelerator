#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  run-vwan-acceptance-test.sh <test-resource-group> <probe-a-vm> <probe-b-vm> <log-analytics-workspace-id> [evidence-directory]

The script proves the permitted TCP 8080 flow and the intentional denied TCP 8081 flow. It uses Azure Run Command; probe VMs do not need public IP addresses or SSH access.
USAGE
}

if [[ $# -lt 4 || $# -gt 5 ]]; then
  usage >&2
  exit 64
fi

for required_command in az python3; do
  command -v "$required_command" >/dev/null || {
    echo "Required command is unavailable: $required_command" >&2
    exit 127
  }
done

test_resource_group="$1"
probe_a_vm_name="$2"
probe_b_vm_name="$3"
workspace_id="$4"
script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
evidence_directory="${5:-$repository_root/artifacts/acceptance-$(date -u +%Y%m%dT%H%M%SZ)}"
query_template="$repository_root/tests/integration/kql/firewall-acceptance.kql"

mkdir -p "$evidence_directory"

probe_a_ip="$(az vm show --resource-group "$test_resource_group" --name "$probe_a_vm_name" --show-details --query privateIps --output tsv | awk '{print $1}')"
probe_b_ip="$(az vm show --resource-group "$test_resource_group" --name "$probe_b_vm_name" --show-details --query privateIps --output tsv | awk '{print $1}')"

if [[ -z "$probe_a_ip" || -z "$probe_b_ip" ]]; then
  echo "Unable to discover private IP addresses for both probes." >&2
  exit 1
fi

cat >"$evidence_directory/test-inputs.json" <<EOF
{
  "generated_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "test_resource_group": "$test_resource_group",
  "probe_a_vm": "$probe_a_vm_name",
  "probe_a_ip": "$probe_a_ip",
  "probe_b_vm": "$probe_b_vm_name",
  "probe_b_ip": "$probe_b_ip",
  "allowed_flow": "TCP 8080",
  "denied_flow": "TCP 8081"
}
EOF

run_on_probe_a() {
  az vm run-command invoke \
    --resource-group "$test_resource_group" \
    --name "$probe_a_vm_name" \
    --command-id RunShellScript \
    --scripts "$1" \
    --output json
}

allowed_command="python3 -c \"import urllib.request; body=urllib.request.urlopen('http://${probe_b_ip}:8080', timeout=15).read().decode(); assert body.strip() == 'taipan-vwan-acceptance-test'; print(body.strip())\""
allowed=false

for attempt in $(seq 1 12); do
  allowed_result="$evidence_directory/allowed-flow-attempt-${attempt}.json"
  if run_on_probe_a "$allowed_command" >"$allowed_result" 2>&1 && grep -q 'taipan-vwan-acceptance-test' "$allowed_result"; then
    allowed=true
    break
  fi
  sleep 15
done

if [[ "$allowed" != true ]]; then
  echo "The required TCP 8080 flow did not succeed. Evidence: $evidence_directory" >&2
  exit 1
fi

denied_command="if timeout 15 bash -c '</dev/tcp/${probe_b_ip}/8081'; then echo UNEXPECTED_CONNECTIVITY; exit 1; else echo EXPECTED_DENY; fi"
denied_result="$evidence_directory/denied-flow.json"
run_on_probe_a "$denied_command" >"$denied_result" 2>&1

if ! grep -q 'EXPECTED_DENY' "$denied_result"; then
  echo "The intentional TCP 8081 deny test did not return the expected result. Evidence: $evidence_directory" >&2
  exit 1
fi

if [[ ! -f "$query_template" ]]; then
  echo "KQL template is missing: $query_template" >&2
  exit 1
fi

query="$(sed \
  -e "s/__PROBE_A_IP__/${probe_a_ip}/g" \
  -e "s/__PROBE_B_IP__/${probe_b_ip}/g" \
  "$query_template")"

printf '%s\n' "$query" >"$evidence_directory/firewall-acceptance.kql"
firewall_logs_found=false

for attempt in $(seq 1 20); do
  firewall_log_result="$evidence_directory/firewall-log-query-attempt-${attempt}.json"
  az monitor log-analytics query \
    --workspace "$workspace_id" \
    --analytics-query "$query" \
    --output json >"$firewall_log_result"

  if grep -q 'Allow' "$firewall_log_result" && grep -q 'Deny' "$firewall_log_result"; then
    firewall_logs_found=true
    break
  fi
  sleep 30
done

if [[ "$firewall_logs_found" != true ]]; then
  echo "Traffic tests completed, but matching allow and deny Firewall logs were not available before the timeout. Evidence: $evidence_directory" >&2
  exit 1
fi

printf 'Acceptance test passed. Evidence: %s\n' "$evidence_directory"
