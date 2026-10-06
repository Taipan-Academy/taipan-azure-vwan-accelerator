#!/usr/bin/env python3
"""Validate deployed workbook configuration and recent POC evidence."""
import json
import runpy
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

validate = runpy.run_path(
    str(Path(__file__).with_name("check-firewall-telemetry.py"))
)["validate"]


def command(args, evidence, name):
    result = subprocess.run(args, text=True, capture_output=True)
    (evidence / (name + ".json")).write_text(result.stdout)
    (evidence / (name + ".stderr")).write_text(result.stderr)
    if result.returncode:
        raise ValueError(name + " failed; inspect its saved stderr.")
    return json.loads(result.stdout)


def resources(module):
    yield from module.get("resources", [])
    for child in module.get("child_modules", []):
        yield from resources(child)


def main():
    evidence_arg, guid, source, destination, started = sys.argv[1:]
    evidence = Path(evidence_arg)
    root = Path(__file__).resolve().parent.parent
    harness = root / "infra/terraform/test-harness"

    # Terraform state may contain secrets. Never save or print its content.
    result = subprocess.run(
        ["terraform", f"-chdir={harness}", "show", "-json"],
        text=True, capture_output=True,
    )
    if result.returncode:
        raise ValueError("Unable to inspect harness state.")
    state = json.loads(result.stdout)
    entries = list(resources(state["values"]["root_module"]))

    def resource(address):
        matches = [
            entry["values"] for entry in entries
            if entry.get("address") == address
        ]
        if len(matches) != 1:
            raise ValueError("Expected state resource missing: " + address)
        return matches[0]

    workspace = resource("azurerm_log_analytics_workspace.test")
    firewall = resource("data.azurerm_firewall.core")
    workbook = resource("azurerm_application_insights_workbook.poc_firewall")

    if workspace["workspace_id"].lower() != guid.lower():
        raise ValueError("Workspace GUID differs from acceptance target.")

    template = (
        harness / "observability/firewall-workbook.json"
    ).read_text()
    expected = json.loads(
        template.replace("__POC_WORKSPACE_RESOURCE_ID__", workspace["id"])
        .replace("__POC_FIREWALL_RESOURCE_ID__", firewall["id"])
    )

    deployed = command(
        [
            "az", "rest", "--method", "get", "--url",
            "https://management.azure.com" + workbook["id"]
            + "?api-version=2021-08-01&canFetchContent=true",
            "--output", "json",
        ],
        evidence, "workbook-deployed",
    )

    if deployed["id"].lower() != workbook["id"].lower():
        raise ValueError("Unexpected deployed workbook ID.")

    properties = deployed["properties"]
    if properties.get("sourceId", "").lower() != workspace["id"].lower():
        raise ValueError("Workbook source workspace is incorrect.")

    document = json.loads(properties["serializedData"])
    if document != expected:
        raise ValueError("Deployed workbook differs from repository definition.")

    contents = [item.get("content") for item in document.get("items", [])]
    start = datetime.fromisoformat(started.replace("Z", "+00:00"))
    cutoff = max(start, datetime.now(timezone.utc) - timedelta(hours=1))
    cutoff_text = cutoff.isoformat().replace("+00:00", "Z")

    for title, kind in (
        ("POC private traffic", "network"),
        ("POC Internet traffic", "application"),
    ):
        matches = [
            content for content in contents
            if isinstance(content, dict) and content.get("title") == title
        ]
        if len(matches) != 1:
            raise ValueError("Missing or duplicate POC table: " + title)

        content = matches[0]
        if content.get("crossComponentResources") != ["{Workspaces}"]:
            raise ValueError("Unexpected workspace selection: " + title)
        if content.get("timeContextFromParameter") != "TimeRange":
            raise ValueError("Unexpected time-range configuration: " + title)

        query = content["query"]
        if "__POC_" in query or "{" in query:
            raise ValueError("Unresolved query parameter: " + title)

        lines = query.splitlines()
        lines.insert(
            1, "| where TimeGenerated >= datetime(" + cutoff_text + ")"
        )
        query = "\n".join(lines)
        (evidence / ("workbook-" + kind + ".kql")).write_text(query + "\n")

        rows = command(
            [
                "az", "monitor", "log-analytics", "query",
                "--workspace", guid,
                "--analytics-query", query,
                "--output", "json",
            ],
            evidence, "workbook-" + kind,
        )
        missing = validate(rows, kind, source, destination)
        if missing:
            raise ValueError(
                f"{title} missing recent decisions: {sorted(missing)}. "
                "Retest to generate fresh evidence; do not mark PASS."
            )
        print("[WORKBOOK] " + title + ": recent expected decisions confirmed.")

    (evidence / "WORKBOOK-VALIDATION.md").write_text(
        "# Workbook validation\n\nStatus: PASS\n\n"
        "Deployed definition and source workspace match the expected configuration.\n"
        "Both POC queries contain all required decisions since test start "
        "and within the last hour.\n"
        "Browser rendering and viewer permissions require visual inspection.\n"
    )
    print("[WORKBOOK] Configuration and query evidence: PASS.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError) as error:
        print("[WORKBOOK] FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
