#!/usr/bin/env python3
"""Validate expected decisions in Azure CLI query result rows."""
import json
import sys

def validate(rows, kind, source, destination):
    if not isinstance(rows, list) or any(
        not isinstance(row, dict) for row in rows
    ):
        raise ValueError("Expected a JSON list of query-result objects.")

    def value(row, name):
        return str(row.get(name, "")).strip()

    if kind == "network":
        required = {("8080", "allow"), ("8081", "deny")}
        observed = {
            (value(row, "DestinationPort"), value(row, "Action").lower())
            for row in rows
            if value(row, "SourceIp") == source
            and value(row, "DestinationIp") == destination
            and value(row, "Protocol").lower() == "tcp"
        }
    elif kind == "application":
        required = {
            ("www.example.com", "allow"),
            ("www.microsoft.com", "deny"),
        }
        observed = {
            (value(row, "Fqdn").lower(), value(row, "Action").lower())
            for row in rows
            if value(row, "SourceIp") == source
            and value(row, "DestinationPort") == "443"
        }
    else:
        raise ValueError("Unknown telemetry kind.")
    return required - observed

if __name__ == "__main__":
    try:
        path, kind, source, destination = sys.argv[1:]
        with open(path) as stream:
            missing = validate(json.load(stream), kind, source, destination)
        if missing:
            print("Waiting for expected firewall decisions:", sorted(missing))
            sys.exit(1)
        print("Exact expected firewall decisions confirmed.")
    except (ValueError, OSError) as error:
        print(f"Telemetry validation error: {error}", file=sys.stderr)
        sys.exit(2)
