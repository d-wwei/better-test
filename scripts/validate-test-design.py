#!/usr/bin/env python3
"""Read-only advisory design-structure validation. Never execute cases or judge products.

Only the documented JSON Schema subset is implemented, driven by the shipped
schema via Better Test hybrid_core; no subject imports, shell, or network access.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path, PurePosixPath
import re
import sys
from typing import Any

# The only non-stdlib import is the shipped Skill helper, never TEST_ROOT code.
sys.dont_write_bytecode = True
from hybrid_core import validate_json_schema

MARKER = "<!-- better-test:case-contract:v1 -->"
MARKER_LINE = re.compile(r"^ {0,3}" + re.escape(MARKER) + r"\s*$")
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
SCHEMA_PATH = Path(__file__).resolve().parent.parent / "schemas/test-design.schema.json"
SUPPORTED = {"$schema", "$id", "title", "description", "$defs", "$ref", "anyOf", "type",
             "required", "properties", "additionalProperties", "items", "minItems",
             "minimum", "pattern", "enum"}


class OperationError(Exception):
    """I/O, arguments or unavailable/unsupported shipped schema; exit 2."""


class Parser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise OperationError(message)


def strict_json(payload: str) -> Any:
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError(f"duplicate JSON key {key!r}")
            result[key] = value
        return result

    def constant(value):
        raise ValueError(f"non-JSON number {value}")

    return json.loads(payload, object_pairs_hook=pairs, parse_constant=constant)


def check_schema_support(schema: dict[str, Any]) -> None:
    """Fail closed if a future schema uses an unsupported assertion keyword."""
    if not isinstance(schema, dict):
        raise OperationError("shipped schema nodes must be objects")
    unknown = set(schema) - SUPPORTED
    if unknown:
        raise OperationError("unsupported schema keyword(s): " + ", ".join(sorted(unknown)))
    ref = schema.get("$ref")
    if ref is not None and (not isinstance(ref, str) or not ref.startswith("#/$defs/")):
        raise OperationError("only local #/$defs/ schema references are supported")
    for name in ("properties", "$defs"):
        if not isinstance(schema.get(name, {}), dict):
            raise OperationError(f"schema {name} must be an object")
        for child in schema.get(name, {}).values():
            check_schema_support(child)
    if not isinstance(schema.get("anyOf", []), list):
        raise OperationError("schema anyOf must be an array")
    for child in schema.get("anyOf", []):
        check_schema_support(child)
    if "items" in schema:
        check_schema_support(schema["items"])


def closing_fence(line: str, opening: str) -> bool:
    match = FENCE.match(line)
    return bool(match and match[1][0] == opening[0] and len(match[1]) >= len(opening)
                and not match[2].strip())


def parse_blocks(text: str) -> tuple[int, list[tuple[int, int, Any]], list[str]]:
    """Ignore all unmarked fenced examples, including markers inside those examples."""
    lines = text.splitlines()
    marked = 0
    cases = []
    errors = []
    index = 0
    enclosing = None
    while index < len(lines):
        line = lines[index]
        if enclosing:
            if closing_fence(line, enclosing):
                enclosing = None
            index += 1
            continue
        if not MARKER_LINE.match(line):
            fence = FENCE.match(line)
            if fence:
                enclosing = fence[1]
            index += 1
            continue
        marked += 1
        marker_line = index + 1
        location = f"block {marked} line {marker_line}"
        index += 1
        while index < len(lines) and not lines[index].strip():
            index += 1
        opener = FENCE.match(lines[index]) if index < len(lines) else None
        if not opener or opener[2].strip() != "json":
            errors.append(f"{location}: marker must immediately precede a fenced json block")
            continue
        start = index + 1
        index = start
        while index < len(lines) and not closing_fence(lines[index], opener[1]):
            index += 1
        if index == len(lines):
            errors.append(f"{location}: unterminated fenced json block")
            continue
        try:
            cases.append((marked, marker_line, strict_json("\n".join(lines[start:index]))))
        except (ValueError, RecursionError) as exc:
            errors.append(f"{location}: malformed JSON: {exc}")
        index += 1
    return marked, cases, errors


def references(case: dict[str, Any]):
    requirements = case.get("requirements")
    if isinstance(requirements, list):
        for index, ref in enumerate(requirements):
            yield f"requirements[{index}]", ref
    for field in ("input_fixture", "oracle_ref", "runner_ref", "environment_ref", "cleanup_ref"):
        if field in case:
            yield field, case[field]
    expected = case.get("expected")
    if isinstance(expected, list):
        for index, item in enumerate(expected):
            if isinstance(item, dict) and "oracle_ref" in item:
                yield f"expected[{index}].oracle_ref", item["oracle_ref"]


def check_reference(ref: Any, root: Path, path: str) -> tuple[list[str], list[str]]:
    errors, warnings = [], []
    if isinstance(ref, dict):
        if ref.get("status") in ("unresolved", "not_applicable"):
            warnings.append(f"{path}: {ref['status']}: {ref.get('reason', '')}")
        return errors, warnings
    if not isinstance(ref, str) or not ref.strip():
        return errors, warnings  # Schema owns malformed Reference shapes.
    if not ref.startswith("test-root:"):
        warnings.append(f"{path}: external_reference_unverified: locator not read or fetched: {ref}")
        return errors, warnings
    locator = ref.removeprefix("test-root:")
    # Literal relative POSIX paths; selectors, anchors and revision suffixes are
    # locators only. No URL decoding, shell expansion or anchor-content reading.
    filename = re.split(r"#|::|@", locator, maxsplit=1)[0]
    relative = PurePosixPath(filename)
    if (not filename or relative.is_absolute() or ".." in relative.parts
            or "\\" in filename or "\x00" in filename):
        return [f"{path}: unsafe_local_reference: expected a relative file within TEST_ROOT"], []
    target = (root / filename).resolve()
    if not target.is_relative_to(root):
        return [f"{path}: unsafe_local_reference: symlink resolves outside TEST_ROOT"], []
    if not target.is_file():
        warnings.append(f"{path}: local_reference_missing: {filename} (execution availability unproven)")
    else:
        warnings.append(f"{path}: local_reference_unverified: file exists; content/selector/anchor/revision not verified")
    return errors, warnings


def inspect(root_arg: str) -> dict[str, Any]:
    root = Path(root_arg).resolve(strict=True)
    if not root.is_dir():
        raise OperationError("--test-root must identify the resolved TEST_ROOT directory")
    groups = (root / "test-groups.md").resolve(strict=True)
    if not groups.is_relative_to(root):
        raise OperationError("test-groups.md resolves outside TEST_ROOT")
    if not groups.is_file():
        raise OperationError("test-groups.md must be a readable file")
    schema = strict_json(SCHEMA_PATH.read_text(encoding="utf-8"))
    check_schema_support(schema)
    marked, cases, errors = parse_blocks(groups.read_text(encoding="utf-8"))
    warnings, case_ids = [], []
    for number, line, case in cases:
        path = f"block {number} line {line}"
        errors.extend(validate_json_schema(case, schema, schema, path))
        if not isinstance(case, dict):
            continue
        case_id = case.get("case_id")
        if isinstance(case_id, str) and case_id.strip():
            if case_id in case_ids:
                errors.append(f"{path}.case_id: duplicate case ID {case_id!r}")
            else:
                case_ids.append(case_id)
        for field, ref in references(case):
            ref_errors, ref_warnings = check_reference(ref, root, f"{path}.{field}")
            errors.extend(ref_errors)
            warnings.extend(ref_warnings)
            if field.startswith("requirements[") and isinstance(ref, str) and "@" not in ref:
                warnings.append(f"{path}.{field}: source_revision_not_fixed: use a fixed revision/digest or explicit unresolved reason")
    if marked:
        warnings.append("semantic_review_required: structure does not prove source/oracle authority, expected correctness, map IDs, executability or detection capability")
    else:
        warnings.append("not_adopted: no marked case-contract v1 blocks; old free-text knowledge was not upgraded or semantically checked")
    return {"schema_version": 1, "scope": "design_structure",
            "status": "invalid" if errors else "valid" if marked else "not_adopted",
            "errors": errors, "warnings": warnings, "case_ids": case_ids}


def main() -> int:
    parser = Parser(description=__doc__)
    parser.add_argument("--test-root", required=True, help="existing resolved TEST_ROOT; no implicit resolver")
    parser.add_argument("--format", choices=("json", "text"), default="text")
    try:
        args = parser.parse_args()
        report = inspect(args.test_root)
    except (OperationError, OSError, ValueError, UnicodeError, RecursionError) as exc:
        report = {"schema_version": 1, "scope": "design_structure", "status": "invalid",
                  "errors": [f"operation_error: {exc}"], "warnings": [], "case_ids": []}
        print(json.dumps(report, ensure_ascii=False))
        print(f"better-test: design checker operation error: {exc}", file=sys.stderr)
        return 2
    if args.format == "json":
        print(json.dumps(report, ensure_ascii=False))
    else:
        print(f"better-test: design_structure status={report['status']}; case_ids={report['case_ids']!r}")
        for field in ("errors", "warnings"):
            for message in report[field]:
                print(f"{field[:-1]}: {message}")
    return 1 if report["status"] == "invalid" else 0


if __name__ == "__main__":
    raise SystemExit(main())
