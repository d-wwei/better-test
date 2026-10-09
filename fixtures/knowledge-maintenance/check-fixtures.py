#!/usr/bin/env python3
"""Frozen fixture integrity only; no case parsing or Agent semantic grading."""
import difflib
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent


def check(root):
    manifest = json.loads((root / 'manifest.json').read_text())
    for name, entry in manifest['scenarios'].items():
        scenario = root / name
        for relative, expected in entry['frozen_sha256'].items():
            file = scenario / relative
            if not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest() != expected:
                raise ValueError(f'{name}: frozen input changed or missing: {relative}')
        before = {p.relative_to(scenario / 'before').as_posix(): p.read_bytes()
                  for p in (scenario / 'before').rglob('*') if p.is_file()}
        after = {p.relative_to(scenario / 'after').as_posix(): p.read_bytes()
                 for p in (scenario / 'after').rglob('*') if p.is_file()}
        changed = {p for p in before.keys() | after.keys() if before.get(p) != after.get(p)}
        if changed != set(entry['allowed_changed_paths']):
            raise ValueError(f'{name}: unexpected snapshot change scope: {sorted(changed)}')
        for relative in entry['preserve_history']:
            if relative not in after or before[relative] != after[relative]:
                raise ValueError(f'{name}: historical artifact changed: {relative}')
        expected_diff = ''.join(difflib.unified_diff(
            (scenario / 'source-before.txt').read_text().splitlines(True),
            (scenario / 'source-after.txt').read_text().splitlines(True),
            fromfile='source-before', tofile='source-after'))
        if (scenario / 'source.diff').read_text() != expected_diff:
            raise ValueError(f'{name}: source diff differs from frozen sources')
    return len(manifest['scenarios'])


class IntegrityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'fixtures'
        shutil.copytree(ROOT, self.root)

    def test_authored_snapshots(self):
        self.assertEqual(check(ROOT), 3)

    def test_reject_rewritten_before(self):
        (self.root / 'semantic-change/before/test-groups.md').write_text('rewritten')
        with self.assertRaisesRegex(ValueError, 'frozen input'):
            check(self.root)

    def test_reject_deleted_source(self):
        (self.root / 'tool-change/source.diff').unlink()
        with self.assertRaisesRegex(ValueError, 'frozen input'):
            check(self.root)

    def test_reject_refactor_changing_case(self):
        with (self.root / 'pure-refactor/after/test-groups.md').open('a') as file:
            file.write('unapproved expected rewrite')
        with self.assertRaisesRegex(ValueError, 'change scope'):
            check(self.root)

    def test_reject_tool_change_rewriting_oracle(self):
        (self.root / 'tool-change/after/reference/requirements.md').write_text('relaxed oracle')
        with self.assertRaisesRegex(ValueError, 'change scope'):
            check(self.root)

    def test_reject_rewritten_history(self):
        (self.root / 'semantic-change/after/history/synthetic-proof.md').write_text('current PASS')
        with self.assertRaisesRegex(ValueError, 'change scope|historical artifact'):
            check(self.root)

    def test_reject_unapproved_extra_file(self):
        (self.root / 'tool-change/after/freshness-registry.json').write_text('{}')
        with self.assertRaisesRegex(ValueError, 'change scope'):
            check(self.root)


if __name__ == '__main__':
    unittest.main(verbosity=2)
