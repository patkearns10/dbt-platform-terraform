#!/usr/bin/env python3
"""
Check that a dbt platform token, account ID, host and connection ID work
together, before running Terraform. Read-only: it creates nothing.

    export DBT_CLOUD_TOKEN=<token>
    python scripts/check_connection.py projects/example

Values are read from the project's terraform.tfvars (and the connection_id
default in its variables.tf). Flags override them:

    python scripts/check_connection.py --account-id 12345 --host-url https://cloud.getdbt.com/api --connection-id 67890

Exit code 0 when every check passes, 1 otherwise. Standard library only.
"""

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

DEFAULT_HOST_URL = "https://cloud.getdbt.com/api"


def read_setting(text, name):
    """Value of a top-level `name = value` line in HCL, or None."""
    match = re.search(rf'^\s*{name}\s*=\s*"?([^"\n#]+?)"?\s*(?:#.*)?$', text, re.MULTILINE)
    return match.group(1).strip() if match else None


def read_variable_default(text, name):
    """Default of `variable "name" { ... default = value ... }`, or None."""
    block = re.search(rf'variable\s+"{name}"\s*\{{(.*?)\n\}}', text, re.DOTALL)
    return read_setting(block.group(1), "default") if block else None


def settings_from_project(project_dir):
    """account_id, host_url and connection_id as Terraform would resolve them."""
    project_dir = Path(project_dir)
    tfvars = project_dir / "terraform.tfvars"
    variables = project_dir / "variables.tf"
    tfvars_text = tfvars.read_text(encoding="utf-8") if tfvars.exists() else ""
    variables_text = variables.read_text(encoding="utf-8") if variables.exists() else ""

    def resolve(name):
        return read_setting(tfvars_text, name) or read_variable_default(variables_text, name)

    return {
        "account_id": resolve("dbt_account_id"),
        "host_url": resolve("dbt_host_url"),
        "connection_id": resolve("connection_id"),
    }


def api_get(host_url, token, path, timeout=30):
    """GET host_url + path. Returns (status, parsed JSON or None, error text or None)."""
    request = urllib.request.Request(
        host_url.rstrip("/") + path,
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, json.loads(response.read().decode("utf-8")), None
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        try:
            message = json.loads(body).get("status", {}).get("user_message") or body
        except ValueError:
            message = body
        return error.code, None, str(message)[:300]
    except (urllib.error.URLError, TimeoutError, ValueError) as error:
        return None, None, str(getattr(error, "reason", error))


def explain(status, error):
    hints = {
        None: "Could not reach the host. Check the host URL and your network.",
        401: "The token was rejected. Check DBT_CLOUD_TOKEN and that the host URL is the one for this account.",
        403: "The token is valid but not allowed to do this.",
        404: "Not found. Check the ID, and that the host URL ends in /api and belongs to this account.",
    }
    hint = hints.get(status, "Unexpected response.")
    return f"{hint} ({status or 'no response'}: {error})"


def run_checks(token, account_id, host_url, connection_id=None):
    """Run all checks. Returns a list of (name, passed, detail)."""
    results = []

    if not token:
        return [("Token", False, "DBT_CLOUD_TOKEN is not set.")]
    if not account_id:
        return [("Account ID", False, "No account ID given.")]
    host_url = (host_url or DEFAULT_HOST_URL).rstrip("/")
    if not host_url.endswith("/api"):
        results.append(("Host URL", False, f"{host_url} should end in /api."))
        return results

    status, body, error = api_get(host_url, token, f"/v2/accounts/{account_id}/")
    if status != 200:
        results.append(("Account", False, explain(status, error)))
        return results
    account = (body or {}).get("data") or {}
    results.append(("Account", True, f'{account.get("name", "?")} (ID {account_id}) at {host_url}'))

    status, body, error = api_get(host_url, token, f"/v3/accounts/{account_id}/projects/?limit=1")
    if status == 200:
        total = ((body or {}).get("extra") or {}).get("pagination", {}).get("total_count")
        detail = "Token can list projects" + (f" ({total} visible)" if total is not None else "")
        results.append(("Projects", True, detail))
    else:
        results.append(("Projects", False, explain(status, error)))

    if connection_id:
        status, body, error = api_get(host_url, token, f"/v3/accounts/{account_id}/connections/{connection_id}/")
        if status == 200:
            connection = (body or {}).get("data") or {}
            adapter = connection.get("adapter_version") or "unknown adapter"
            passed = "snowflake" in str(adapter).lower() or adapter == "unknown adapter"
            detail = f'{connection.get("name", "?")} (ID {connection_id}, {adapter})'
            if not passed:
                detail += ". This is not a Snowflake connection."
            results.append(("Connection", passed, detail))
        else:
            results.append(("Connection", False, explain(status, error)))

    return results


def main():
    parser = argparse.ArgumentParser(description="Check dbt platform token, account, host and connection.")
    parser.add_argument("project_dir", nargs="?", help="Project directory to read settings from, e.g. projects/example")
    parser.add_argument("--account-id")
    parser.add_argument("--host-url")
    parser.add_argument("--connection-id")
    args = parser.parse_args()

    settings = settings_from_project(args.project_dir) if args.project_dir else {}
    account_id = args.account_id or settings.get("account_id") or os.environ.get("DBT_CLOUD_ACCOUNT_ID")
    host_url = args.host_url or settings.get("host_url") or os.environ.get("DBT_CLOUD_HOST_URL")
    connection_id = args.connection_id or settings.get("connection_id")

    results = run_checks(os.environ.get("DBT_CLOUD_TOKEN"), account_id, host_url, connection_id)
    for name, passed, detail in results:
        print(f'{"PASS" if passed else "FAIL"}  {name}: {detail}')

    ok = all(passed for _, passed, _ in results)
    if ok:
        print("\nAll checks passed. This confirms the token can read the account;")
        print("creating projects and groups also needs it to have account-level admin rights.")
    else:
        print("\nFix the failed check, then run this again.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
