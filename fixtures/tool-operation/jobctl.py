"""Thin synthetic CLI: one request, no implicit retry or auto-reconciliation."""
import argparse
from contextlib import closing
import http.client
import json
from pathlib import Path
import sqlite3
import sys
import urllib.error
import urllib.request
from urllib.parse import urlencode, urlsplit

OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--endpoint")
    parser.add_argument("--tenant", choices=("T1", "T2"), default="T1")
    parser.add_argument("--profile", choices=("writer", "denied"), default="writer")
    parser.add_argument("--correlation")
    parser.add_argument("--timeout", type=float, default=5)
    commands = parser.add_subparsers(dest="command", required=True)
    submit = commands.add_parser("submit")
    submit.add_argument("--key", required=True)
    submit.add_argument("--payload", required=True, help="literal JSON payload")
    get = commands.add_parser("get")
    get.add_argument("--key", required=True)
    control = commands.add_parser("control")
    control.add_argument("--owner", required=True)
    control.add_argument("--values", required=True)
    opaque = commands.add_parser("opaque")
    opaque.add_argument("--payload", required=True)
    snapshot = commands.add_parser("snapshot")
    snapshot.add_argument("--db", required=True)
    args = parser.parse_args()
    if args.command == "snapshot":
        # Independent readonly store observer; does not call list/API or create an absent DB.
        database = Path(args.db).resolve()
        with closing(sqlite3.connect(database.as_uri() + "?mode=ro", uri=True)) as db:
            db.row_factory = sqlite3.Row
            result = {table: [dict(row) for row in db.execute(f"SELECT * FROM {table} ORDER BY rowid")]
                for table in ("notes", "jobs", "outbox", "history_reads", "opaque_writes")}
        print(json.dumps(result, ensure_ascii=False))
        return 0
    if not args.endpoint:
        parser.error("--endpoint required for HTTP commands")
    endpoint = urlsplit(args.endpoint)
    if endpoint.scheme != "http" or endpoint.hostname != "127.0.0.1" or not endpoint.port or endpoint.path or endpoint.query or endpoint.fragment:
        parser.error("endpoint must be the fixture's literal http://127.0.0.1:port origin")
    method, path, body = "POST", "/jobs", None
    headers = {"Content-Type": "application/json", "X-Tenant": args.tenant, "X-Profile": args.profile}
    if args.correlation:
        headers["X-Correlation-ID"] = args.correlation
    if args.command == "submit":
        body = {"key": args.key, "payload": json.loads(args.payload)}
    elif args.command == "get":
        method, path = "GET", "/jobs?" + urlencode({"key": args.key})
    elif args.command == "control":
        path, body = "/__control", json.loads(args.values)
        headers["X-Fixture-Owner"] = args.owner
    elif args.command == "opaque":
        path, body = "/opaque", {"payload": json.loads(args.payload)}
    request = urllib.request.Request(args.endpoint + path, method=method, headers=headers,
        data=None if body is None else json.dumps(body).encode())
    try:
        try:
            response = OPENER.open(request, timeout=args.timeout)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            result = {"http_status": response.status, "body": json.loads(response.read())}
        print(json.dumps(result, ensure_ascii=False))
        return 0 if 200 <= result["http_status"] < 300 else 1
    except (urllib.error.URLError, http.client.RemoteDisconnected, TimeoutError,
            ConnectionError, http.client.IncompleteRead) as error:
        print(json.dumps({"transport_error": type(error).__name__, "outcome": "unknown",
            "automatic_retries": 0}), file=sys.stderr)
        return 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (sqlite3.Error, OSError, ValueError) as error:
        print(json.dumps({"operation_error": type(error).__name__, "automatic_retries": 0}), file=sys.stderr)
        sys.exit(2)
