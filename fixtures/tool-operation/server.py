"""Loopback-only synthetic notes/jobs service. No real accounts or queue clients."""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import math
import os
from pathlib import Path
import signal
import socket
import sqlite3
import threading
import time
from urllib.parse import parse_qs, urlsplit
import uuid

DEFAULTS = {"shortcut_disabled": False, "note_body_loss": False,
    "note_response_delay": 0.0, "global_key": False, "late_auth": False,
    "duplicate_outbox": False, "drop_job_response_once": False,
    "observer_broken": False, "job_barrier": 0}


def digest(payload):
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":"),
        ensure_ascii=False).encode()).hexdigest()


class State:
    def __init__(self, args):
        self.args = args
        self.directory = Path(args.data_dir).resolve()
        self.directory.mkdir(parents=True, exist_ok=True)
        self.database = self.directory / "state.sqlite3"
        if self.database.exists():
            raise ValueError("use a fresh owned data directory; database already exists")
        self.controls = dict(DEFAULTS)
        self.lock = threading.RLock()
        self.trace_lock = threading.Lock()
        self.barrier = None
        self.started = time.monotonic()
        self.identity = {"run_id": args.run_id, "instance_id": uuid.uuid4().hex,
            "pid": os.getpid(), "database": str(self.database),
            "data_dir": str(self.directory), "started_at": datetime.now(timezone.utc).isoformat()}
        with self.connect() as db:
            db.executescript("""
                CREATE TABLE notes (id TEXT PRIMARY KEY, title TEXT NOT NULL, body TEXT NOT NULL);
                CREATE TABLE jobs (id TEXT PRIMARY KEY, tenant TEXT NOT NULL, key TEXT NOT NULL,
                    payload TEXT NOT NULL, digest TEXT NOT NULL, UNIQUE(tenant,key));
                CREATE TABLE outbox (sequence INTEGER PRIMARY KEY, namespace TEXT NOT NULL,
                    tenant TEXT NOT NULL, job_id TEXT NOT NULL, payload TEXT NOT NULL);
                CREATE TABLE history_reads (sequence INTEGER PRIMARY KEY, tenant TEXT NOT NULL,
                    key TEXT NOT NULL, profile TEXT NOT NULL, correlation TEXT NOT NULL);
                CREATE TABLE opaque_writes (sequence INTEGER PRIMARY KEY, payload TEXT NOT NULL);
            """)

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.database, timeout=5)
        db.row_factory = sqlite3.Row
        try:
            with db:
                yield db
        finally:
            db.close()

    def emit(self, event, **values):
        row = {"time": datetime.now(timezone.utc).isoformat(), "monotonic": time.monotonic(),
            "event": event, "run_id": self.identity["run_id"],
            "instance_id": self.identity["instance_id"], **values}
        with self.trace_lock, open(self.directory / "trace.jsonl", "a", encoding="utf-8") as stream:
            stream.write(json.dumps(row, ensure_ascii=False) + "\n")

    def ready(self):
        return not self.args.never_ready and time.monotonic() - self.started >= self.args.ready_delay

    def read_history(self, db, tenant, key, profile, correlation):
        if not self.controls["observer_broken"]:
            db.execute("INSERT INTO history_reads(tenant,key,profile,correlation) VALUES(?,?,?,?)",
                (tenant, key, profile, correlation))
            self.emit("history_read", tenant=tenant, key=key, profile=profile, correlation=correlation)


class Handler(BaseHTTPRequestHandler):
    server_version = "BetterTestSynthetic/1"

    @property
    def state(self):
        return self.server.state

    def log_message(self, *args):
        pass  # structured trace is the raw request/operation observer

    def send_json(self, status, data):
        data = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            self.state.emit("observer_client_disconnected", path=self.path)

    def body(self):
        size = int(self.headers.get("Content-Length", "0"))
        if size > 65536:
            raise ValueError("fixture request too large")
        value = json.loads(self.rfile.read(size))
        if not isinstance(value, dict):
            raise ValueError("expected JSON object")
        return value

    def subject(self):
        return self.headers.get("X-Tenant", "T1"), self.headers.get("X-Profile", "writer")

    def request_trace(self, body=None):
        correlation = self.headers.get("X-Correlation-ID") or uuid.uuid4().hex
        tenant, profile = self.subject()
        self.state.emit("request", method=self.command, path=self.path, tenant=tenant,
            profile=profile, correlation=correlation, body=body)
        return correlation

    def reject_subject(self, tenant, profile):
        if tenant not in ("T1", "T2") or profile not in ("writer", "denied"):
            self.send_json(400, {"rejected": True})
            return True
        return False

    def do_GET(self):
        parsed = urlsplit(self.path)
        path = parsed.path
        if path == "/identity":
            return self.send_json(200, self.state.identity)
        correlation = self.request_trace()
        if path == "/ready":
            ready = self.state.ready()
            return self.send_json(200 if ready else 503, {**self.state.identity, "ready": ready})
        if path == "/ui-config":
            return self.send_json(200, {"shortcut_disabled": self.state.controls["shortcut_disabled"],
                "instance_id": self.state.identity["instance_id"]})
        if path in ("/", "/app.js"):
            name = "index.html" if path == "/" else "app.js"
            content = (Path(__file__).parent / name).read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8" if path == "/" else "application/javascript")
            self.send_header("Content-Length", str(len(content)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(content)
            return
        with self.state.lock, self.state.connect() as db:
            if path == "/notes":
                return self.send_json(200, [dict(row) for row in db.execute("SELECT * FROM notes ORDER BY id")])
            if path.startswith("/notes/"):
                row = db.execute("SELECT * FROM notes WHERE id=?", (path[len("/notes/"):],)).fetchone()
                return self.send_json(200 if row else 404, dict(row) if row else {"not_found": True})
            if path == "/jobs" or path.startswith("/jobs/"):
                tenant, profile = self.subject()
                if self.reject_subject(tenant, profile):
                    return
                if profile != "writer":
                    return self.send_json(403, {"denied": True})
                key = parse_qs(parsed.query).get("key", [None])[0]
                self.state.read_history(db, tenant, key or "id-lookup", profile, correlation)
                if path == "/jobs":
                    row = db.execute("SELECT * FROM jobs WHERE tenant=? AND key=?", (tenant, key)).fetchone()
                else:
                    row = db.execute("SELECT * FROM jobs WHERE tenant=? AND id=?", (tenant, path[len("/jobs/"):])).fetchone()
                db.commit()
                return self.send_json(200 if row else 404, self.job(row) if row else {"not_found": True})
        self.send_json(404, {"not_found": True})

    def job(self, row):
        return {"id": row["id"], "tenant": row["tenant"], "key": row["key"],
            "payload": json.loads(row["payload"]), "digest": row["digest"]}

    def do_POST(self):
        try:
            body = self.body()
        except (ValueError, json.JSONDecodeError):
            return self.send_json(400, {"rejected": True})
        correlation = self.request_trace(body)
        if self.path == "/__control":
            if self.headers.get("X-Fixture-Owner") != self.state.identity["run_id"]:
                return self.send_json(403, {"denied": True})
            if set(body) - set(DEFAULTS):
                return self.send_json(400, {"rejected": True, "unknown_control": True})
            for key, value in body.items():
                if key == "job_barrier":
                    valid = type(value) is int and value in (0, 2)
                elif key == "note_response_delay":
                    valid = type(value) in (int, float) and 0 <= value <= 5
                else:
                    valid = type(value) is bool
                if not valid:
                    return self.send_json(400, {"rejected": True, "invalid_control": key})
            with self.state.lock:
                self.state.controls.update(body)
                if "job_barrier" in body:
                    self.state.barrier = threading.Barrier(2, timeout=3) if body["job_barrier"] else None
            self.state.emit("control", values=body, correlation=correlation)
            return self.send_json(200, self.state.controls)
        if self.path == "/__ui-event":
            # Records actual page handler entries, including a trigger ignored while submitting.
            if set(body) != {"action", "state"} or body["action"] not in ("button", "shortcut", "cancel", "open", "close"):
                return self.send_json(400, {"rejected": True})
            self.state.emit("ui_event", **body, correlation=correlation)
            return self.send_json(200, {"recorded": True})
        if not self.state.ready():
            return self.send_json(503, {"ready": False})
        if self.path == "/notes":
            if not isinstance(body.get("title"), str) or not isinstance(body.get("body"), str):
                return self.send_json(400, {"rejected": True})
            if not body["title"].strip():
                return self.send_json(422, {"rejected": True, "field": "title"})
            with self.state.lock, self.state.connect() as db:
                note_id = uuid.uuid4().hex
                note_body = "" if self.state.controls["note_body_loss"] else body["body"]
                db.execute("INSERT INTO notes VALUES(?,?,?)", (note_id, body["title"].strip(), note_body))
                db.commit()
                delay = self.state.controls["note_response_delay"]
                self.state.emit("note_committed", id=note_id, title=body["title"].strip(),
                    body=note_body, correlation=correlation)
            if delay:
                self.state.emit("note_reply_wait", seconds=delay, correlation=correlation)
                time.sleep(delay)
            self.state.emit("note_reply", id=note_id, correlation=correlation)
            return self.send_json(201, {"id": note_id, "saved": True})
        if self.path == "/opaque":
            with self.state.lock, self.state.connect() as db:
                db.execute("INSERT INTO opaque_writes(payload) VALUES(?)", (json.dumps(body),))
                db.commit()
            self.state.emit("opaque_committed_no_receipt", correlation=correlation)
            return self.drop_response(correlation)
        if self.path != "/jobs":
            return self.send_json(404, {"not_found": True})
        self.submit_job(body, correlation)

    def drop_response(self, correlation):
        self.state.emit("response_dropped", correlation=correlation)
        self.close_connection = True
        self.connection.shutdown(socket.SHUT_RDWR)
        self.connection.close()

    def submit_job(self, body, correlation):
        tenant, profile = self.subject()
        if self.reject_subject(tenant, profile):
            return
        key = body.get("key")
        if not isinstance(key, str) or not key or "payload" not in body:
            return self.send_json(400, {"rejected": True})
        with self.state.lock:
            if profile != "writer" and not self.state.controls["late_auth"]:
                return self.send_json(403, {"denied": True})
            barrier = self.state.barrier
        if barrier is not None:
            self.state.emit("barrier_entered", tenant=tenant, key=key, correlation=correlation)
            try:
                barrier.wait()
            except threading.BrokenBarrierError:
                return self.send_json(503, {"fixture_barrier_timeout": True})
            self.state.emit("barrier_released", correlation=correlation)
            with self.state.lock:
                if self.state.barrier is barrier:
                    self.state.barrier = None
        with self.state.lock, self.state.connect() as db:
            payload_digest = digest(body["payload"])
            self.state.read_history(db, tenant, key, profile, correlation)
            if self.state.controls["global_key"]:
                existing = db.execute("SELECT * FROM jobs WHERE key=?", (key,)).fetchone()
            else:
                existing = db.execute("SELECT * FROM jobs WHERE tenant=? AND key=?", (tenant, key)).fetchone()
            if profile != "writer":
                db.commit()
                response = {"denied": True}
                if existing:
                    response["historical"] = self.job(existing)
                return self.send_json(403, response)
            if existing:
                db.commit()
                if existing["digest"] != payload_digest:
                    return self.send_json(409, {"conflict": True})
                return self.send_json(200, self.job(existing))
            job_id = uuid.uuid4().hex
            payload_json = json.dumps(body["payload"], sort_keys=True, ensure_ascii=False)
            db.execute("INSERT INTO jobs VALUES(?,?,?,?,?)", (job_id, tenant, key, payload_json, payload_digest))
            for _ in range(2 if self.state.controls["duplicate_outbox"] else 1):
                db.execute("INSERT INTO outbox(namespace,tenant,job_id,payload) VALUES(?,?,?,?)",
                    (self.state.identity["run_id"], tenant, job_id, payload_json))
            db.commit()
            self.state.emit("job_committed", tenant=tenant, key=key, id=job_id,
                digest=payload_digest, correlation=correlation)
            drop = self.state.controls["drop_job_response_once"]
            self.state.controls["drop_job_response_once"] = False
        if drop:
            return self.drop_response(correlation)
        return self.send_json(201, {"id": job_id, "tenant": tenant, "key": key,
            "payload": body["payload"], "digest": payload_digest})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", required=True)
    parser.add_argument("--identity-file", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--ready-delay", type=float, default=0)
    parser.add_argument("--never-ready", action="store_true")
    args = parser.parse_args()
    if not args.run_id.strip() or not math.isfinite(args.ready_delay) or args.ready_delay < 0:
        parser.error("run-id must be nonempty and ready-delay nonnegative")
    identity_file = Path(args.identity_file).resolve()
    if identity_file.exists():
        parser.error("identity file already exists; do not overwrite another instance")
    state = State(args)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.daemon_threads = True
    server.state = state
    state.identity["endpoint"] = f"http://127.0.0.1:{server.server_address[1]}"
    identity_file.parent.mkdir(parents=True, exist_ok=True)
    # Lifecycle identity and raw artifacts intentionally survive shutdown.
    state.emit("launched", **{k: v for k, v in state.identity.items() if k not in ("run_id", "instance_id")})
    pending_identity = identity_file.with_name(identity_file.name + ".pending")
    with open(pending_identity, "x", encoding="utf-8") as stream:
        stream.write(json.dumps(state.identity, indent=2) + "\n")
    pending_identity.replace(identity_file)
    print(json.dumps(state.identity), flush=True)
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(SystemExit(0)))
    try:
        server.serve_forever(poll_interval=.1)
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
