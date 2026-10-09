"""Owned synthetic fixture lifecycle only; never a generic product runner."""
import argparse
import json
import math
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def read_identity(path):
    identity = json.loads(Path(path).read_text())
    endpoint = urlsplit(identity["endpoint"])
    if endpoint.scheme != "http" or endpoint.hostname != "127.0.0.1" or not endpoint.port or endpoint.path or endpoint.query or endpoint.fragment:
        raise ValueError("unsafe or non-fixture endpoint")
    if type(identity["pid"]) is not int or identity["pid"] <= 1:
        raise ValueError("unsafe PID")
    return identity


def live(identity, route="/identity"):
    with OPENER.open(identity["endpoint"] + route, timeout=1) as response:
        observed = json.load(response)
    for key in ("run_id", "instance_id", "pid", "database", "data_dir", "started_at", "endpoint"):
        if observed.get(key) != identity[key]:
            raise ValueError("identity mismatch: " + key)
    return observed


def doctor(identity, deadline):
    live(identity)
    expires = time.monotonic() + deadline
    last = None
    while True:
        try:
            last = live(identity, "/ready")
            if last["ready"]:
                return {"ready": True, "identity": identity}
        except urllib.error.HTTPError as error:
            if error.code != 503:
                raise
            observed = json.load(error)
            for key in ("run_id", "instance_id", "pid"):
                if observed.get(key) != identity[key]:
                    raise ValueError("readiness identity mismatch")
            last = observed
        remaining = expires - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("readiness deadline exhausted; last=" + json.dumps(last))
        time.sleep(min(.05, remaining))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    launch = commands.add_parser("launch")
    launch.add_argument("--data-dir", required=True)
    launch.add_argument("--identity", required=True)
    launch.add_argument("--run-id", required=True)
    launch.add_argument("--ready-delay", type=float, default=0)
    launch.add_argument("--never-ready", action="store_true")
    launch.add_argument("--deadline", type=float, default=5)
    for command in ("doctor", "stop"):
        subparser = commands.add_parser(command)
        subparser.add_argument("--identity", required=True)
        subparser.add_argument("--owner", required=True, help="original run ID, supplied independently of identity file")
        subparser.add_argument("--deadline", type=float, default=5)
    args = parser.parse_args()
    if not math.isfinite(args.deadline) or args.deadline <= 0:
        parser.error("deadline must be finite and positive")
    if args.command == "launch":
        directory = Path(args.data_dir).resolve()
        identity_file = Path(args.identity).resolve()
        if identity_file.exists() or (directory / "state.sqlite3").exists():
            raise ValueError("refuse to overwrite owned identity/database")
        directory.mkdir(parents=True, exist_ok=True)
        argv = [sys.executable, str(ROOT / "server.py"), "--data-dir", str(directory),
            "--identity-file", str(identity_file), "--run-id", args.run_id,
            "--ready-delay", str(args.ready_delay)]
        if args.never_ready:
            argv.append("--never-ready")
        with open(directory / "launch.log", "xb") as stream:
            process = subprocess.Popen(argv, stdout=stream, stderr=stream, start_new_session=True)
        expires = time.monotonic() + args.deadline
        try:
            while time.monotonic() < expires and process.poll() is None:
                if identity_file.exists():
                    identity = read_identity(identity_file)
                    if identity["pid"] != process.pid or identity["run_id"] != args.run_id:
                        raise ValueError("launched child identity mismatch")
                    live(identity)
                    print(json.dumps(identity))
                    return 0
                time.sleep(.02)
            raise TimeoutError("launch failed; retained launch.log")
        except BaseException:
            # We own the exact child even if binding/identity inspection failed.
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=3)
            raise
    identity = read_identity(args.identity)
    if identity["run_id"] != args.owner:
        raise ValueError("original actor owner mismatch")
    if args.command == "doctor":
        print(json.dumps(doctor(identity, args.deadline)))
        return 0
    live(identity)  # Stop fails closed for dead/unreachable/ambiguous targets; no name-based kill.
    os.kill(identity["pid"], signal.SIGTERM)
    expires = time.monotonic() + args.deadline
    while time.monotonic() < expires:
        process = subprocess.run(["ps", "-p", str(identity["pid"]), "-o", "stat="],
            capture_output=True, text=True, check=False)
        if not process.stdout.strip() or process.stdout.lstrip().startswith("Z"):
            print(json.dumps({"stopped_pid": identity["pid"], "evidence_removed": False}))
            return 0
        time.sleep(.05)
    raise TimeoutError("cleanup deadline exhausted; evidence retained; no SIGKILL escalation")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, TimeoutError, OSError, KeyError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(2)
