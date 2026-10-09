#!/usr/bin/env python3
"""Exercise the real read-only CLI; isolated temporary knowledge, never product runs."""
import copy
import http.server
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[2]
CHECKER = ROOT / "scripts/validate-test-design.py"
MARKER = "<!-- better-test:case-contract:v1 -->"
VALID = json.loads((Path(__file__).parent / "valid.json").read_text())


def block(case):
    return MARKER + "\n```json\n" + json.dumps(case, ensure_ascii=False) + "\n```\n"


class DesignChecker(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="bt-design-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "test-root"
        self.root.mkdir()
        for filename in ("reference/jobs-v2.md", "reference/job-small.json", "oracle-catalog.md",
                         "tools/test_jobs.py", "env-config.md", "tools/jobs-fixture.py"):
            target = self.root / filename
            target.parent.mkdir(exist_ok=True)
            target.write_text("Synthetic design reference. Not product execution.\n")
        self.case = copy.deepcopy(VALID)
        self.groups = self.root / "test-groups.md"

    def call(self, text=None, args=None, checker=CHECKER):
        self.assertTrue(checker.is_file(), "M1 read-only checker is not implemented")
        if text is not None:
            self.groups.write_text(text, encoding="utf-8")
        result = subprocess.run([sys.executable, str(checker)] + (args if args is not None else
                                ["--test-root", str(self.root), "--format", "json"]),
                                capture_output=True, text=True, timeout=8)
        self.assertTrue(result.stdout.strip(), ("CLI must emit an output record", result.stderr))
        return result.returncode, json.loads(result.stdout), result.stderr

    def check(self, text, code, status):
        rc, data, stderr = self.call(text)
        self.assertEqual(rc, code, (data, stderr))
        self.assertEqual(data["status"], status)
        self.assertEqual(data["scope"], "design_structure")
        self.assertEqual(data["schema_version"], 1)
        for field in ("errors", "warnings", "case_ids"):
            self.assertIsInstance(data[field], list)
        return data

    def test_valid_multi_expected_no_business_verdict(self):
        data = self.check(block(self.case), 0, "valid")
        self.assertEqual(data["case_ids"], ["J-02"])
        self.assertEqual(data["errors"], [])
        self.assertTrue(any("semantic_review_required" in w for w in data["warnings"]))
        self.assertNotIn("verdict", data)

    def test_legacy_and_unmarked_examples(self):
        for text in ("# Legacy\n- J-02 retry, expected one durable job\n",
                     "```json\n" + json.dumps(self.case) + "\n```\n",
                     "````markdown\n" + block(self.case) + "````\n"):
            with self.subTest(text=text):
                data = self.check(text, 0, "not_adopted")
                self.assertEqual(data["case_ids"], [])
                self.assertTrue(any("not_adopted" in w for w in data["warnings"]))

    def test_missing_files_and_argument_errors_are_operational(self):
        for args in (None, [], ["--test-root", str(self.root), "--format", "xml"],
                     ["--test-root", str(self.root / "missing"), "--format", "json"]):
            with self.subTest(args=args):
                rc, data, _ = self.call(args=args)
                self.assertEqual(rc, 2)
                self.assertTrue(any("operation_error" in e for e in data["errors"]))
        self.groups.symlink_to(Path(self.tmp.name) / "outside.md")
        self.groups.resolve().write_text(block(self.case))
        self.assertEqual(self.call()[0], 2)

    def test_broken_marked_blocks_cannot_fall_back(self):
        for text in (MARKER, MARKER + "\nparagraph\n" + block(self.case),
                     MARKER + "\n```python\n{}\n```", MARKER + "\n```json\n{}",
                     MARKER + "\n```json\n{broken}\n```",
                     MARKER + "\n```json\n[]\n```"):
            with self.subTest(text=text):
                data = self.check(text, 1, "invalid")
                self.assertTrue(any("line " in e for e in data["errors"]))

    def test_missing_fields_wrong_types_and_empty_values(self):
        for field in VALID:
            case = copy.deepcopy(VALID)
            del case[field]
            with self.subTest(missing=field):
                data = self.check(block(case), 1, "invalid")
                self.assertTrue(any(field in e for e in data["errors"]))
        mutations = [("revision", True), ("revision", 0), ("revision", 1.5), ("revision", 1.0), ("case_id", "  "),
                     ("requirements", []), ("entries", [3]), ("features", "F"),
                     ("risk", {"failure": "x", "priority": "urgent"}), ("actions", [""]),
                     ("expected", [{"observe": "job_id"}]), ("evidence_required", []),
                     ("input_fixture", {"status": "unresolved", "reason": " "}),
                     ("oracle_ref", {"status": "verified", "reason": "self asserted"})]
        for field, value in mutations:
            case = copy.deepcopy(VALID)
            case[field] = value
            with self.subTest(field=field, value=value):
                self.check(block(case), 1, "invalid")

    def test_committed_invalid_fixture(self):
        case = json.loads((Path(__file__).parent / "invalid.json").read_text())
        data = self.check(block(case), 1, "invalid")
        for field in ("revision", "requirements", "priority", "relation"):
            self.assertTrue(any(field in e for e in data["errors"]))

    def test_duplicate_ids_keys_and_non_json_numbers(self):
        self.check(block(self.case) + block(self.case), 1, "invalid")
        for payload in ('{"case_id":"J-02","case_id":"J-03"}',
                        json.dumps(self.case).replace('"revision": 1', '"revision": NaN'),
                        json.dumps(self.case).replace('"revision": 1', '"revision": Infinity')):
            self.check(MARKER + "\n```json\n" + payload + "\n```", 1, "invalid")

    def test_unresolved_and_missing_references_are_distinct(self):
        self.case["oracle_ref"] = {"status": "unresolved", "reason": "contract not approved"}
        self.case["input_fixture"] = "test-root:not-created.json"
        self.case["cleanup_ref"] = {"status": "not_applicable", "reason": "pure immutable fixture"}
        self.case["requirements"] = ["spec/jobs-v2.md#AC-2"]
        data = self.check(block(self.case), 0, "valid")
        for code in ("unresolved", "local_reference_missing", "not_applicable", "source_revision_not_fixed",
                     "external_reference_unverified", "semantic_review_required"):
            self.assertTrue(any(code in w for w in data["warnings"]), code)

    def test_path_escape_and_symlink_escape_are_rejected(self):
        outside = Path(self.tmp.name) / "private.md"
        outside.write_text("must never read outside TEST_ROOT")
        (self.root / "escape.md").symlink_to(outside)
        for ref in ("test-root:../private.md", "test-root:" + str(outside),
                    "test-root:escape.md", "test-root:", "test-root:tools\\test_jobs.py"):
            with self.subTest(ref=ref):
                self.case["oracle_ref"] = ref
                data = self.check(block(self.case), 1, "invalid")
                self.assertTrue(any("unsafe_local_reference" in e for e in data["errors"]))

    def test_commands_urls_and_external_paths_are_not_executed_or_fetched(self):
        requests = []
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append(self.path)
                self.send_response(200)
                self.end_headers()
            def log_message(self, *args):
                pass
        server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            sentinel = Path(self.tmp.name) / "EXECUTED"
            self.case["actions"] = [f"touch {sentinel}"]
            self.case["runner_ref"] = f"$(touch {sentinel})"
            self.case["cleanup_ref"] = "file:///etc/passwd"
            self.case["requirements"] = [f"http://127.0.0.1:{server.server_port}/source"]
            data = self.check(block(self.case), 0, "valid")
            self.assertFalse(sentinel.exists())
            self.assertEqual(requests, [])
            self.assertTrue(any("external_reference_unverified" in w for w in data["warnings"]))
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_wrong_implementation_golden_remains_structurally_valid(self):
        self.case["expected"] = [{"observe": "outbox count", "relation": "same as broken product output", "value": 2}]
        self.case["oracle_ref"] = "src/new_job_handler.py#current-output"
        data = self.check(block(self.case), 0, "valid")
        self.assertTrue(any("semantic_review_required" in w for w in data["warnings"]))

    def test_complete_ui_api_blocks_and_arbitrary_json_values(self):
        for name, case_id in (("ui-example.md", "U-02"), ("api-example.md", "J-02")):
            with self.subTest(example=name):
                data = self.check((Path(__file__).parent / name).read_text(), 0, "valid")
                self.assertEqual(data["case_ids"], [case_id])
        for value in (None, False, 0, "", [False, None, 0], {"nested": [0, False]}):
            with self.subTest(value=value):
                self.case["expected"][0]["value"] = value
                self.check(block(self.case), 0, "valid")

    def test_no_writes_or_external_file_content_reads(self):
        outside = Path(self.tmp.name) / "private-source.md"
        outside.write_text("PRIVATE CONTENT MUST NOT BE OPENED")
        self.case["requirements"] = [str(outside)]
        self.groups.write_text(block(self.case))
        before = {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob("*") if p.is_file()}
        wrapper = (
            "import sys,runpy,pathlib; forbidden=sys.argv[1]; checker=sys.argv[2]; root=sys.argv[3]; "
            "sys.path.insert(0,str(pathlib.Path(checker).parent)); "
            "sys.argv=[checker,'--test-root',root,'--format','json']; "
            "sys.addaudithook(lambda event,args: (_ for _ in ()).throw(RuntimeError('outside open')) "
            "if event=='open' and str(args[0])==forbidden else None); "
            "runpy.run_path(checker,run_name='__main__')"
        )
        result = subprocess.run([sys.executable, "-c", wrapper, str(outside), str(CHECKER), str(self.root)],
                                capture_output=True, text=True, timeout=8)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["status"], "valid")
        after = {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob("*") if p.is_file()}
        self.assertEqual(before, after)

    def test_tilde_fence_blank_separator_and_multiple_ids(self):
        second = copy.deepcopy(self.case)
        second["case_id"] = "J-13"
        text = "# Test groups\n" + block(self.case) + "\n" + MARKER + "\n\n~~~json\n" + json.dumps(second) + "\n~~~~\n"
        data = self.check(text, 0, "valid")
        self.assertEqual(data["case_ids"], ["J-02", "J-13"])
        self.assertTrue(any("block 2 line 7" in w for w in data["warnings"]))

    def test_schema_is_the_structural_source(self):
        self.assertTrue(CHECKER.is_file(), "M1 read-only checker is not implemented")
        copied = Path(self.tmp.name) / "skill"
        (copied / "scripts").mkdir(parents=True)
        (copied / "schemas").mkdir()
        shutil.copy(CHECKER, copied / "scripts" / CHECKER.name)
        shutil.copy(ROOT / "scripts/hybrid_core.py", copied / "scripts/hybrid_core.py")
        schema = json.loads((ROOT / "schemas/test-design.schema.json").read_text())
        schema["properties"]["risk"]["properties"]["priority"]["enum"] = ["critical"]
        (copied / "schemas/test-design.schema.json").write_text(json.dumps(schema))
        self.assertEqual(self.call(block(self.case), checker=copied / "scripts" / CHECKER.name)[0], 1)
        self.case["risk"]["priority"] = "critical"
        self.assertEqual(self.call(block(self.case), checker=copied / "scripts" / CHECKER.name)[0], 0)
        self.assertFalse((copied / "scripts/__pycache__").exists())
        schema["unevaluatedProperties"] = False
        (copied / "schemas/test-design.schema.json").write_text(json.dumps(schema))
        rc, data, _ = self.call(block(self.case), checker=copied / "scripts" / CHECKER.name)
        self.assertEqual(rc, 2)
        self.assertTrue(any("unsupported schema keyword" in e for e in data["errors"]))
        (copied / "schemas/test-design.schema.json").write_text("[]")
        rc, data, _ = self.call(block(self.case), checker=copied / "scripts" / CHECKER.name)
        self.assertEqual(rc, 2)
        self.assertTrue(any("operation_error" in e for e in data["errors"]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
