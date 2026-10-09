"""Checks synthetic apparatus semantics, never Agent/browser workflow proof."""
import concurrent.futures
from contextlib import closing
import hashlib
import http.client
import json
import os
from pathlib import Path
import sqlite3
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


class Fixture(unittest.TestCase):
    def setUp(self):
        self.assertTrue((ROOT / "server.py").is_file(), "runnable fixture server missing")
        self.temp = tempfile.TemporaryDirectory(prefix="bt-operation-selftest-")
        self.resources = []
        self.instance = self.launch("selftest")

    def launch(self, run_id, *args):
        directory = Path(self.temp.name) / run_id
        directory.mkdir()
        identity = directory / "identity.json"
        stream = open(directory / "launch.log", "wb")
        process = subprocess.Popen([sys.executable, str(ROOT / "server.py"),
            "--data-dir", str(directory), "--identity-file", str(identity),
            "--run-id", run_id, *args], stdout=stream, stderr=stream)
        resource = {"process": process, "stream": stream, "directory": directory}
        self.resources.append(resource)
        deadline = time.monotonic() + 5
        while not identity.exists() and process.poll() is None and time.monotonic() < deadline:
            time.sleep(.02)
        self.assertTrue(identity.exists(), (directory / "launch.log").read_text())
        resource.update(json.loads(identity.read_text()))
        return resource

    def request(self, method, path, body=None, tenant="T1", profile="writer", instance=None):
        instance = instance or self.instance
        headers = {"X-Tenant": tenant, "X-Profile": profile,
            "X-Fixture-Owner": instance["run_id"], "Content-Type": "application/json"}
        req = urllib.request.Request(instance["endpoint"] + path,
            data=None if body is None else json.dumps(body).encode(), method=method, headers=headers)
        try:
            response = OPENER.open(req, timeout=5)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            data = response.read().decode()
            return response.status, json.loads(data) if data.startswith("{") or data.startswith("[") else data

    def control(self, **values):
        status, result = self.request("POST", "/__control", values)
        self.assertEqual(status, 200, result)

    def snapshot(self, instance=None):
        instance = instance or self.instance
        with closing(sqlite3.connect(Path(instance['database']).as_uri() + "?mode=ro", uri=True)) as db:
            db.row_factory = sqlite3.Row
            return {table: [dict(row) for row in db.execute(f"SELECT * FROM {table}")]
                for table in ("notes", "jobs", "outbox", "history_reads", "opaque_writes")}

    def trace(self):
        return [json.loads(line) for line in (self.instance["directory"] / "trace.jsonl").read_text().splitlines()]

    def submit(self, payload=None, **kwargs):
        return self.request("POST", "/jobs", {"key": "K", "payload": payload or {"task": "P1"}}, **kwargs)

    def test_notes_persist_trim_reject_and_reopen(self):
        status, note = self.request("POST", "/notes", {"title": "  Sprint note  ", "body": "draft-A"})
        self.assertEqual(status, 201)
        self.assertEqual(self.request("GET", "/notes/" + note["id"])[1]["title"], "Sprint note")
        self.assertEqual(self.snapshot()["notes"][0]["body"], "draft-A")
        before = self.snapshot()["notes"]
        status, rejected = self.request("POST", "/notes", {"title": "   ", "body": "no"})
        self.assertTrue(rejected["rejected"])
        self.assertEqual(self.snapshot()["notes"], before)
        self.assertIn('id="save"', self.request("GET", "/")[1])

    def test_note_controls_are_independent_and_reachable(self):
        self.control(shortcut_disabled=True)
        self.assertTrue(self.request("GET", "/ui-config")[1]["shortcut_disabled"])
        self.control(shortcut_disabled=False, note_body_loss=True)
        self.assertFalse(self.request("GET", "/ui-config")[1]["shortcut_disabled"])
        status, note = self.request("POST", "/notes", {"title": "note", "body": "draft-A"})
        self.assertEqual(status, 201)
        self.assertEqual(self.request("GET", "/notes/" + note["id"])[1]["body"], "")

    def test_job_replay_conflict_cli_and_exact_effects(self):
        status, job = self.submit()
        self.assertEqual(status, 201)
        command = [sys.executable, str(ROOT / "jobctl.py"), "--endpoint", self.instance["endpoint"],
            "submit", "--key", "K", "--payload", '{"task":"P1"}']
        result = subprocess.run(command, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["body"]["id"], job["id"])
        self.assertEqual(json.loads(result.stdout)["http_status"], 200)
        self.assertEqual(self.submit({"task": "P2"})[0], 409)
        state = self.snapshot()
        self.assertEqual((len(state["jobs"]), len(state["outbox"])), (1, 1))
        self.assertEqual(json.loads(state["jobs"][0]["payload"]), {"task": "P1"})

    def test_tenant_isolation_and_global_key_fault(self):
        self.submit()
        self.assertEqual(self.submit({"task": "P2"}, tenant="T2")[0], 201)
        state = self.snapshot()
        self.assertEqual({row["tenant"] for row in state["jobs"]}, {"T1", "T2"})
        self.assertEqual(len(state["outbox"]), 2)
        foreign_id = next(row["id"] for row in state["jobs"] if row["tenant"] == "T1")
        self.assertTrue(self.request("GET", "/jobs/" + foreign_id, tenant="T2")[1]["not_found"])
        self.control(global_key=True)
        self.assertEqual(self.request("POST", "/jobs", {"key": "global", "payload": {"task": "P1"}})[0], 201)
        self.assertEqual(self.request("POST", "/jobs", {"key": "global", "payload": {"task": "P2"}}, tenant="T2")[0], 409)

    def test_denied_history_observer_positive_control_and_late_auth_fault(self):
        self.submit()
        self.submit()  # positive control: authorized replay reads history
        reads = len(self.snapshot()["history_reads"])
        self.assertGreater(reads, 0)
        status, response = self.submit(profile="denied")
        self.assertTrue(response["denied"])
        self.assertNotIn("id", response)
        self.assertEqual(len(self.snapshot()["history_reads"]), reads)
        self.control(late_auth=True)
        status, response = self.submit(profile="denied")
        self.assertTrue(response["denied"])
        self.assertGreater(len(self.snapshot()["history_reads"]), reads)
        self.assertIn("historical", response)

    def test_observer_fault_is_visible_in_positive_control(self):
        self.submit()
        self.control(observer_broken=True)
        before = self.snapshot()["history_reads"]
        self.submit()
        self.assertEqual(self.snapshot()["history_reads"], before)

    def test_committed_response_loss_reconcile_then_idempotent_replay(self):
        self.control(drop_job_response_once=True)
        with self.assertRaises((http.client.RemoteDisconnected, urllib.error.URLError)):
            self.submit()
        status, existing = self.request("GET", "/jobs?key=K")
        self.assertEqual(status, 200)
        status, replay = self.submit()
        self.assertEqual(status, 200)
        self.assertEqual(existing["id"], replay["id"])
        state = self.snapshot()
        self.assertEqual((len(state["jobs"]), len(state["outbox"])), (1, 1))
        events = [row["event"] for row in self.trace()]
        self.assertLess(events.index("job_committed"), events.index("response_dropped"))

    def test_unqueryable_write_has_one_trace_and_no_receipt_interface(self):
        with self.assertRaises((http.client.RemoteDisconnected, urllib.error.URLError)):
            self.request("POST", "/opaque", {"payload": "once"})
        status, result = self.request("GET", "/opaque")
        self.assertEqual(status, 404)
        self.assertTrue(result["not_found"])
        self.assertEqual(len(self.snapshot()["opaque_writes"]), 1)

    def test_concurrency_barrier_records_overlap_and_final_invariants(self):
        self.control(job_barrier=2)
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            responses = list(pool.map(lambda _: self.submit(), range(2)))
        self.assertEqual(len({body["id"] for status, body in responses}), 1)
        state = self.snapshot()
        self.assertEqual((len(state["jobs"]), len(state["outbox"])), (1, 1))
        events = [row["event"] for row in self.trace()]
        first_release = events.index("barrier_released")
        self.assertEqual(events[:first_release].count("barrier_entered"), 2)

    def test_outbox_fault_changes_effect_despite_success(self):
        self.control(duplicate_outbox=True)
        self.assertEqual(self.submit()[0], 201)
        self.assertEqual(len(self.snapshot()["outbox"]), 2)

    def test_ready_delay_and_never_ready(self):
        delayed = self.launch("delayed", "--ready-delay", "0.3")
        self.assertFalse(self.request("GET", "/ready", instance=delayed)[1]["ready"])
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            if self.request("GET", "/ready", instance=delayed)[1]["ready"]:
                break
            time.sleep(.02)
        self.assertTrue(self.request("GET", "/ready", instance=delayed)[1]["ready"])
        never = self.launch("never", "--never-ready")
        self.assertFalse(self.request("GET", "/ready", instance=never)[1]["ready"])

    def test_cleanup_identity_guard_and_evidence_survival(self):
        other = self.launch("other")
        identity_file = self.instance["directory"] / "identity.json"
        command = [sys.executable, str(ROOT / "lifecycle.py"), "stop", "--owner", "selftest", "--identity", str(identity_file)]
        forged = self.instance["directory"] / "forged.json"
        identity = json.loads(identity_file.read_text())
        identity["endpoint"] = other["endpoint"]
        forged.write_text(json.dumps(identity))
        wrong = subprocess.run([*command[:-1], str(forged)], capture_output=True, text=True, timeout=5)
        self.assertNotEqual(wrong.returncode, 0)
        self.assertIsNone(other["process"].poll())
        self.submit()
        trace = self.instance["directory"] / "trace.jsonl"
        before = hashlib.sha256(trace.read_bytes()).hexdigest()
        stopped = subprocess.run(command, capture_output=True, text=True, timeout=5)
        self.assertEqual(stopped.returncode, 0, stopped.stderr)
        self.instance["process"].wait(timeout=3)
        self.assertEqual(hashlib.sha256(trace.read_bytes()).hexdigest(), before)
        self.assertTrue(identity_file.is_file())
        self.assertIsNone(other["process"].poll())

    def test_cli_response_loss_reports_unknown_without_resending(self):
        self.control(drop_job_response_once=True)
        command = [sys.executable, str(ROOT / "jobctl.py"), "--endpoint", self.instance["endpoint"],
            "submit", "--key", "K", "--payload", '{"task":"P1"}']
        result = subprocess.run(command, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(json.loads(result.stderr)["automatic_retries"], 0)
        self.assertEqual(json.loads(result.stderr)["outcome"], "unknown")
        writes = [row for row in self.trace() if row["event"] == "request" and row["method"] == "POST" and row["path"] == "/jobs"]
        self.assertEqual(len(writes), 1)

    def test_cli_store_observer_failure_does_not_create_database(self):
        missing = Path(self.temp.name) / "missing.sqlite3"
        result = subprocess.run([sys.executable, str(ROOT / "jobctl.py"), "snapshot", "--db", str(missing)],
            capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 2)
        self.assertFalse(missing.exists())
        self.assertIn("operation_error", json.loads(result.stderr))

    def test_control_owner_and_type_validation(self):
        request = urllib.request.Request(self.instance["endpoint"] + "/__control", method="POST",
            data=b'{"note_body_loss": true}', headers={"X-Fixture-Owner": "other"})
        with self.assertRaises(urllib.error.HTTPError) as context:
            OPENER.open(request, timeout=2)
        self.assertEqual(context.exception.code, 403)
        context.exception.close()
        self.assertEqual(self.request("POST", "/__control", {"global_key": "false"})[0], 400)

    def test_lifecycle_requires_original_actor_owner(self):
        identity = self.instance["directory"] / "identity.json"
        base = [sys.executable, str(ROOT / "lifecycle.py"), "doctor", "--identity", str(identity)]
        correct = subprocess.run([*base, "--owner", "selftest"], capture_output=True, text=True, timeout=5)
        self.assertEqual(correct.returncode, 0, correct.stderr)
        wrong = subprocess.run([*base, "--owner", "someone-else"], capture_output=True, text=True, timeout=5)
        self.assertEqual(wrong.returncode, 2)
        self.assertIn("owner", wrong.stderr)
        self.assertIsNone(self.instance["process"].poll())

    def test_lifecycle_doctor_deadline_and_launch_entry(self):
        directory = Path(self.temp.name) / "managed"
        identity = directory / "identity.json"
        command = [sys.executable, str(ROOT / "lifecycle.py"), "launch", "--data-dir", str(directory),
            "--identity", str(identity), "--run-id", "managed", "--never-ready"]
        launched = subprocess.run(command, capture_output=True, text=True, timeout=5)
        self.assertEqual(launched.returncode, 0, launched.stderr)
        base = [sys.executable, str(ROOT / "lifecycle.py")]
        try:
            diagnosed = subprocess.run([*base, "doctor", "--owner", "managed", "--identity", str(identity), "--deadline", ".1"],
                capture_output=True, text=True, timeout=3)
            self.assertEqual(diagnosed.returncode, 2)
            self.assertIn("deadline exhausted", diagnosed.stderr)
            self.assertTrue((directory / "trace.jsonl").is_file())
        finally:
            stopped = subprocess.run([*base, "stop", "--owner", "managed", "--identity", str(identity)],
                capture_output=True, text=True, timeout=6)
            self.assertEqual(stopped.returncode, 0, stopped.stderr)

    @unittest.skipUnless(shutil.which("node"), "optional installed Node absent; JS handler apparatus NOT_RUN")
    def test_ui_handler_pending_write_survives_observer_failure(self):
        self.control(note_response_delay=.3)
        result = subprocess.run([shutil.which("node"), str(ROOT / "check-ui.js"), self.instance["endpoint"], "pending"],
            capture_output=True, text=True, timeout=6)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    @unittest.skipUnless(shutil.which("node"), "optional installed Node absent; JS handler apparatus NOT_RUN")
    def test_ui_handler_unknown_write_requires_reconcile(self):
        result = subprocess.run([shutil.which("node"), str(ROOT / "check-ui.js"), self.instance["endpoint"], "unknown"],
            capture_output=True, text=True, timeout=6)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
    def tearDown(self):
        for resource in reversed(self.resources):
            # Test harness owns these exact Popen objects; no name-based kill.
            process = resource["process"]
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=5)
            resource["stream"].close()
        self.temp.cleanup()  # selftest scratch only, never Agent evidence


if __name__ == "__main__":
    unittest.main(verbosity=2)
