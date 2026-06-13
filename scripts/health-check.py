#!/usr/bin/env python3
"""
Checks health of all deployments and nodes in an AKS cluster.
Exits non-zero if any deployment is unavailable or any node is NotReady.
"""
import subprocess
import json
import sys


def run(cmd: list[str]) -> dict:
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return json.loads(result.stdout)


def check_nodes() -> list[str]:
    data = run(["kubectl", "get", "nodes", "-o", "json"])
    issues = []
    for node in data["items"]:
        name = node["metadata"]["name"]
        conditions = {c["type"]: c["status"] for c in node["status"]["conditions"]}
        if conditions.get("Ready") != "True":
            issues.append(f"Node NOT Ready: {name}")
    return issues


def check_deployments() -> list[str]:
    data = run(["kubectl", "get", "deployments", "-A", "-o", "json"])
    issues = []
    for dep in data["items"]:
        name = dep["metadata"]["name"]
        ns = dep["metadata"]["namespace"]
        desired = dep["spec"]["replicas"] or 0
        available = dep["status"].get("availableReplicas") or 0
        if available < desired:
            issues.append(f"Deployment {ns}/{name}: {available}/{desired} replicas available")
    return issues


def main():
    issues = check_nodes() + check_deployments()
    if issues:
        print("HEALTH CHECK FAILED:")
        for issue in issues:
            print(f"  - {issue}")
        sys.exit(1)
    print("All nodes and deployments healthy.")


if __name__ == "__main__":
    main()
