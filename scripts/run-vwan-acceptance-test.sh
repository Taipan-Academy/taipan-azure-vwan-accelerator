#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  run-vwan-acceptance-test.sh <test-resource-group> <probe-a-vm> <probe-b-vm> <log-analytics-workspace-id> [evidence-directory]

The script proves permitted and denied private flows plus controlled Internet egress. It uses Azure Run Command; probe VMs do not need public IP addresses or SSH access.
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
application_query_template="$repository_root/tests/integration/kql/firewall-internet-egress.kql"

mkdir -p "$evidence_directory"
chmod 700 "$evidence_directory"
test_start_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

for template in "$query_template" "$application_query_template"; do
  [[ -s "$template" ]] || {
    echo "Missing or empty KQL template: $template" >&2
    exit 1
  }
done

[[ -f "$script_directory/check-firewall-telemetry.py" ]] || {
  echo "Telemetry validator is missing." >&2
  exit 1
}

# TAIPAN_PROGRESS_V1
echo "[TEST] Discovering probe IP addresses..."
printf "[EVIDENCE] %s\n" "$evidence_directory"
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
  "denied_flow": "TCP 8081",
  "internet_allowed": "HTTPS www.example.com:443",
  "internet_denied": "HTTPS www.microsoft.com:443"
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

printf "[TEST 1/4] TCP 8080: %s -> %s; expecting Allow...\n" "$probe_a_ip" "$probe_b_ip"
allowed_command="python3 -c \"import urllib.request; body=urllib.request.urlopen('http://${probe_b_ip}:8080', timeout=15).read().decode(); assert body.strip() == 'taipan-vwan-acceptance-test'; print(body.strip())\""
allowed=false

for attempt in $(seq 1 12); do
  echo "[TEST 1/4] Connection attempt $attempt/12"
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

echo "[PASS 1/4] TCP 8080 succeeded."
echo "[TEST 2/4] TCP 8081; expecting blocked connectivity..."
denied_command="if timeout 15 bash -c '</dev/tcp/${probe_b_ip}/8081'; then echo UNEXPECTED_CONNECTIVITY; exit 1; else echo EXPECTED_DENY; fi"
denied_result="$evidence_directory/denied-flow.json"
run_on_probe_a "$denied_command" >"$denied_result" 2>&1

if ! grep -q 'EXPECTED_DENY' "$denied_result"; then
  echo "The intentional TCP 8081 deny test did not return the expected result. Evidence: $evidence_directory" >&2
  exit 1
fi

echo "[PASS 2/4] TCP 8081 returned expected blocked connectivity."
echo "[TEST 3/4] HTTPS www.example.com:443; expecting Allow..."
internet_allowed_command="HTTPS_PROXY= HTTP_PROXY= ALL_PROXY= https_proxy= http_proxy= all_proxy= python3 -c \"import urllib.request; response=urllib.request.urlopen('https://www.example.com', timeout=20); assert response.status == 200; print('EXPECTED_INTERNET_ALLOW', response.status)\""
internet_allowed_result="$evidence_directory/internet-allowed.json"
run_on_probe_a "$internet_allowed_command" >"$internet_allowed_result" 2>&1

if ! grep -q 'EXPECTED_INTERNET_ALLOW' "$internet_allowed_result"; then
  echo "The approved Internet egress test did not return the expected result. Evidence: $evidence_directory" >&2
  exit 1
fi

echo "[PASS 3/4] Approved HTTPS request succeeded."
echo "[TEST 4/4] HTTPS www.microsoft.com:443; expecting blocked connectivity..."
internet_denied_command="if HTTPS_PROXY= HTTP_PROXY= ALL_PROXY= https_proxy= http_proxy= all_proxy= python3 -c \"import urllib.request; urllib.request.urlopen('https://www.microsoft.com', timeout=20)\"; then echo UNEXPECTED_INTERNET_CONNECTIVITY; exit 1; else echo EXPECTED_INTERNET_DENY; fi"
internet_denied_result="$evidence_directory/internet-denied.json"
run_on_probe_a "$internet_denied_command" >"$internet_denied_result" 2>&1

if ! grep -q 'EXPECTED_INTERNET_DENY' "$internet_denied_result"; then
  echo "The blocked Internet egress test did not return the expected result. Evidence: $evidence_directory" >&2
  exit 1
fi

echo "[PASS 4/4] Blocked HTTPS request returned expected failure."
echo "[TELEMETRY] Confirming exact firewall Allow/Deny decisions for this test run."
echo "[TELEMETRY] Log ingestion may take several minutes; retries are automatic."

# TAIPAN_TELEMETRY_REFRESH_V1
refresh_test_traffic() {
  local phase="$1" attempt="$2"
  local command expected_first expected_second
  local result="$evidence_directory/traffic-refresh-${phase}-attempt-${attempt}.json"

  case "$phase" in
    network)
      command="$(printf 'set -e\n%s\n%s\n' "$allowed_command" "$denied_command")"
      expected_first="taipan-vwan-acceptance-test"
      expected_second="EXPECTED_DENY"
      ;;
    application)
      command="$(printf 'set -e\n%s\n%s\n' "$internet_allowed_command" "$internet_denied_command")"
      expected_first="EXPECTED_INTERNET_ALLOW"
      expected_second="EXPECTED_INTERNET_DENY"
      ;;
    *)
      echo "Unknown traffic refresh phase: $phase" >&2
      return 2
      ;;
  esac

  echo "[TELEMETRY] Refreshing $phase test traffic; query attempt $attempt/20."
  if ! run_on_probe_a "$command" >"$result" 2>"$result.stderr"; then
    echo "Traffic refresh command failed. Evidence: $result" >&2
    return 1
  fi

  if ! grep -q "$expected_first" "$result" ||
     ! grep -q "$expected_second" "$result" ||
     grep -Eq 'UNEXPECTED_CONNECTIVITY|UNEXPECTED_INTERNET_CONNECTIVITY' "$result"; then
    echo "Traffic refresh did not preserve the expected outcomes. Evidence: $result" >&2
    return 1
  fi
}

if [[ ! -f "$query_template" ]]; then
  echo "KQL template is missing: $query_template" >&2
  exit 1
fi

query="$(sed \
  -e "s/__PROBE_A_IP__/${probe_a_ip}/g" \
  -e "s/__PROBE_B_IP__/${probe_b_ip}/g" \
  "$query_template")"

query="${query/TimeGenerated > ago(60m)/TimeGenerated >= datetime($test_start_utc)}"
printf '%s\n' "$query" >"$evidence_directory/firewall-acceptance.kql"
firewall_logs_found=false

for attempt in $(seq 1 20); do
  # Four bounded refreshes, including when the log table is not ready.
  case "$attempt" in
    2|6|10|14) refresh_test_traffic network "$attempt" || exit 1 ;;
  esac
  firewall_log_result="$evidence_directory/firewall-log-query-attempt-${attempt}.json"
  if ! az monitor log-analytics query \
    --workspace "$workspace_id" \
    --analytics-query "$query" \
    --output json >"$firewall_log_result" 2>"$firewall_log_result.stderr"; then
    cat "$firewall_log_result.stderr" >&2
    # New resource-specific tables may not exist until ingestion.
    if grep -Eiq "Failed to resolve table|does not refer to any known table" "$firewall_log_result.stderr"; then
      echo "[TELEMETRY] Waiting for log-table ingestion..."
      sleep 30
      continue
    fi
    echo "Log query failed; review the saved stderr file." >&2
    exit 1
  fi

  echo "[TELEMETRY] Network attempt $attempt/20"
  if python3 "$script_directory/check-firewall-telemetry.py" \
    "$firewall_log_result" network "$probe_a_ip" "$probe_b_ip"; then
    firewall_logs_found=true
    break
  else
    validator_status=$?
    if [[ "$validator_status" != 1 ]]; then
      echo "Invalid telemetry output; stopping instead of retrying." >&2
      exit "$validator_status"
    fi
  fi
  sleep 30
done

if [[ "$firewall_logs_found" != true ]]; then
  echo "Traffic tests completed, but matching allow and deny Firewall logs were not available before the timeout. Evidence: $evidence_directory" >&2
  exit 1
fi

application_query="$(sed -e "s/__PROBE_A_IP__/${probe_a_ip}/g" "$application_query_template")"
application_query="${application_query/TimeGenerated > ago(60m)/TimeGenerated >= datetime($test_start_utc)}"
printf '%s\n' "$application_query" >"$evidence_directory/firewall-internet-egress.kql"
application_logs_found=false

for attempt in $(seq 1 20); do
  # Four bounded refreshes, including when the log table is not ready.
  case "$attempt" in
    2|6|10|14) refresh_test_traffic application "$attempt" || exit 1 ;;
  esac
  application_log_result="$evidence_directory/firewall-application-log-query-attempt-${attempt}.json"
  if ! az monitor log-analytics query \
    --workspace "$workspace_id" \
    --analytics-query "$application_query" \
    --output json >"$application_log_result" 2>"$application_log_result.stderr"; then
    cat "$application_log_result.stderr" >&2
    # New resource-specific tables may not exist until ingestion.
    if grep -Eiq "Failed to resolve table|does not refer to any known table" "$application_log_result.stderr"; then
      echo "[TELEMETRY] Waiting for log-table ingestion..."
      sleep 30
      continue
    fi
    echo "Log query failed; review the saved stderr file." >&2
    exit 1
  fi

  echo "[TELEMETRY] Application attempt $attempt/20"
  if python3 "$script_directory/check-firewall-telemetry.py" \
    "$application_log_result" application "$probe_a_ip" "$probe_b_ip"; then
    application_logs_found=true
    break
  else
    validator_status=$?
    if [[ "$validator_status" != 1 ]]; then
      echo "Invalid telemetry output; stopping instead of retrying." >&2
      exit "$validator_status"
    fi
  fi
  sleep 30
done

if [[ "$application_logs_found" != true ]]; then
  echo "Internet tests completed, but matching allow and deny Firewall application logs were not available before the timeout. Evidence: $evidence_directory" >&2
  exit 1
fi

cat >"$evidence_directory/REPORT.md" <<REPORT
# Azure vWAN acceptance-test report

**Status:** PASS
**Generated (UTC):** $(date -u +%Y-%m-%dT%H:%M:%SZ)

| Check | Result | Evidence |
| --- | --- | --- |
| Private flow: Probe A to Probe B TCP 8080 | PASS | \`allowed-flow-attempt-*.json\` |
| Private flow: Probe A to Probe B TCP 8081 | PASS (blocked) | \`denied-flow.json\` |
| Internet egress: www.example.com HTTPS | PASS (allowed) | \`internet-allowed.json\` |
| Internet egress: www.microsoft.com HTTPS | PASS (blocked) | \`internet-denied.json\` |
| Azure Firewall network-rule telemetry | PASS | \`firewall-log-query-attempt-*.json\` |
| Azure Firewall application-rule telemetry | PASS | \`firewall-application-log-query-attempt-*.json\` |

**Test resource group:** \`${test_resource_group}\`
**Probe A:** \`${probe_a_vm_name}\` (\`${probe_a_ip}\`)
**Probe B:** \`${probe_b_vm_name}\` (\`${probe_b_ip}\`)
REPORT

printf 'Acceptance test passed. Report: %s/REPORT.md\n' "$evidence_directory"
