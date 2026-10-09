"""Owned synthetic fixture lifecycle only; never a generic product runner."""
import argparse
from contextlib import contextmanager
import http.client
import json
import math
import os
from pathlib import Path
import signal
import subprocess
import sys
import threading
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


def live(identity, route="/identity", timeout=1):
    with OPENER.open(identity["endpoint"] + route, timeout=timeout) as response:
        observed = json.load(response)
    for key in ("run_id", "instance_id", "pid", "database", "data_dir", "started_at", "endpoint"):
        if observed.get(key) != identity[key]:
            raise ValueError("identity mismatch: " + key)
    return observed


@contextmanager
def observation_deadline(expires):
    """Fixture CLI owns a POSIX main-thread alarm; no surviving observer worker."""
    if os.name != "posix" or threading.current_thread() is not threading.main_thread():
        raise ValueError("absolute lifecycle deadline requires main-thread POSIX execution")
    if any(signal.getitimer(signal.ITIMER_REAL)):
        raise ValueError("absolute observation timer already owned; refuse to replace it")
    budget = expires - time.monotonic()
    if budget <= 0:
        raise TimeoutError("absolute HTTP observation deadline expired")
    previous_handler = signal.getsignal(signal.SIGALRM)

    def expire(*_):
        raise TimeoutError("absolute HTTP observation deadline expired")

    signal.signal(signal.SIGALRM, expire)
    try:
        signal.setitimer(signal.ITIMER_REAL, budget)
        yield
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous_handler)


def doctor(identity, deadline):
    expires = time.monotonic() + deadline
    last = None
    phase = "identity"

    def deadline_error(error=None):
        diagnostic = "" if error is None else f"; diagnostic={type(error).__name__}: {error}"
        return TimeoutError(f"readiness deadline exhausted; phase={phase}; last={json.dumps(last)}{diagnostic}")

    def remaining():
        budget = expires - time.monotonic()
        if budget <= 0:
            raise deadline_error()
        return budget

    def observe(route):
        try:
            with observation_deadline(expires):
                try:
                    return live(identity, route, timeout=remaining())
                except urllib.error.HTTPError as error:
                    if route != "/ready" or error.code != 503:
                        raise
                    with error:
                        observed = json.load(error)
                    for key in ("run_id", "instance_id", "pid"):
                        if observed.get(key) != identity[key]:
                            raise ValueError("readiness identity mismatch")
                    return observed
        except (TimeoutError, urllib.error.URLError, http.client.HTTPException) as error:
            if time.monotonic() >= expires:
                raise deadline_error(error) from error
            raise  # early network/read failure keeps its original classification/diagnostic

    last = observe("/identity")
    remaining()
    phase = "ready"
    while True:
        last = observe("/ready")
        budget = remaining()  # never report ready after the shared budget expires
        if last["ready"]:
            return {"ready": True, "identity": identity}
        time.sleep(min(.05, budget))


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
            # Discovery and all identity bytes share one budget after we own the exact child.
            with observation_deadline(expires):
                while time.monotonic() < expires and process.poll() is None:
                    if identity_file.exists():
                        identity = read_identity(identity_file)
                        if identity["pid"] != process.pid or identity["run_id"] != args.run_id:
                            raise ValueError("launched child identity mismatch")
                        budget = expires - time.monotonic()
                        if budget <= 0:
                            raise TimeoutError("launch deadline exhausted; retained launch.log")
                        live(identity, timeout=budget)
                        if time.monotonic() >= expires:
                            raise TimeoutError("launch deadline exhausted; retained launch.log")
                        print(json.dumps(identity))
                        return 0
                    time.sleep(min(.02, max(0, expires - time.monotonic())))
                raise TimeoutError("launch failed within discovery deadline; retained launch.log")
        except BaseException as error:
            failure = error
            if isinstance(error, TimeoutError) or (isinstance(error, (urllib.error.URLError, http.client.HTTPException))
                    and time.monotonic() >= expires):
                failure = TimeoutError(f"launch discovery deadline exhausted; diagnostic={type(error).__name__}: "
                    f"{error}; evidence retained")
            # Separate bounded recovery budget; never signal an unrelated PID or remove evidence.
            try:
                if process.poll() is None:
                    process.terminate()
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                raise TimeoutError(f"launch failed: {failure}; owned child cleanup deadline exhausted; "
                    f"pid={process.pid}; evidence retained; no SIGKILL escalation") from error
            if failure is not error:
                raise failure from error
            raise
    if args.command == "stop":
        expires = time.monotonic() + args.deadline
        phase, last = "identity", None

        def remaining():
            budget = expires - time.monotonic()
            if budget <= 0:
                raise TimeoutError(f"cleanup deadline exhausted; phase={phase}; evidence retained")
            return budget

        try:
            # Includes local identity, HTTP headers/body, pre-signal check, ps and bounded sleeps.
            with observation_deadline(expires):
                identity = read_identity(args.identity)
                if identity["run_id"] != args.owner:
                    raise ValueError("original actor owner mismatch")
                last = live(identity, timeout=remaining())
                phase = "pre_signal"
                remaining()  # a late/mismatched identity must never authorize SIGTERM
                os.kill(identity["pid"], signal.SIGTERM)
                phase = "process_state"
                while True:
                    process = subprocess.run(["ps", "-p", str(identity["pid"]), "-o", "stat="],
                        capture_output=True, text=True, check=False, timeout=remaining())
                    remaining()  # never turn a late process probe into cleanup success
                    last = {"pid": identity["pid"], "stat": process.stdout, "returncode": process.returncode,
                        "stderr": process.stderr}
                    if process.returncode not in (0, 1) or (process.returncode == 1 and process.stderr.strip()):
                        raise OSError("process-state observer failed: " + process.stderr)
                    if not process.stdout.strip() or process.stdout.lstrip().startswith("Z"):
                        print(json.dumps({"stopped_pid": identity["pid"], "evidence_removed": False}))
                        return 0
                    time.sleep(min(.05, remaining()))
        except (TimeoutError, urllib.error.URLError, http.client.HTTPException, subprocess.TimeoutExpired) as error:
            if time.monotonic() >= expires:
                raise TimeoutError(f"cleanup deadline exhausted; phase={phase}; last={json.dumps(last)}; "
                    f"diagnostic={type(error).__name__}: {error}; evidence retained; no SIGKILL escalation") from error
            raise
    identity = read_identity(args.identity)
    if identity["run_id"] != args.owner:
        raise ValueError("original actor owner mismatch")
    if args.command == "doctor":
        print(json.dumps(doctor(identity, args.deadline)))
        return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, TimeoutError, OSError, KeyError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(2)
