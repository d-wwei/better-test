#!/usr/bin/env python3
"""Negative controls for source-only fixture packaging, not a reviewer trial."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent


class PackagingChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="bt-m4-packaging-")
        self.addCleanup(self.temp.cleanup)
        self.fixture = Path(self.temp.name) / "team-review"
        shutil.copytree(ROOT, self.fixture)

    def check(self, code, reason):
        result = subprocess.run(
            ["python3", str(self.fixture / "check-packaging.py")],
            text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        self.assertIn(reason, result.stdout)

    def test_complete_source_slices(self):
        self.check(0, "6 A/B source slices; static only; semantic rehearsal NOT_RUN")

    def test_stage_a_cannot_link_to_author_case_slice(self):
        (self.fixture / "shortcut-gap/phase-a.md").write_text(
            "# Phase A\n[author](phase-b.md)\n", encoding="utf-8",
        )
        self.check(1, "phase A must expose exactly its source.md")

    def test_missing_stage_b_is_reported(self):
        (self.fixture / "shared-golden/phase-b.md").unlink()
        self.check(1, "missing shared-golden/phase-b.md")

    def test_source_reference_must_resolve(self):
        (self.fixture / "shared-desktop/source.md").unlink()
        self.check(1, "unavailable local input source.md")


if __name__ == "__main__":
    unittest.main(verbosity=2)
