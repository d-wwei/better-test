#!/usr/bin/env python3
"""Project, canonicalize, and compare Better Test results v3/v4 documents."""

from __future__ import annotations

import argparse
import copy
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from hybrid_core import (
    canonicalize_results,
    dump_json,
    load_json,
    semantic_diff,
    sha256_json,
    v3_to_v4,
    validate_results_v4,
    write_atomic,
    write_atomic_bytes,
)


def artifact_refs(document: dict, schema: int) -> set[str]:
    refs: set[str] = set()
    for item in document.get("items", []):
        for source in item.get("evidence_sources", []):
            ref = source.get("artifact_ref")
            if isinstance(ref, str):
                refs.add(ref)
    if schema == 3:
        hybrid = document.get("hybrid", {})
        if isinstance(hybrid, dict):
            for artifact in hybrid.get("artifacts", {}).values():
                if isinstance(artifact, dict) and isinstance(artifact.get("artifact_ref"), str):
                    refs.add(artifact["artifact_ref"])
    else:
        input_refs = document.get("input_refs")
        if isinstance(input_refs, dict):
            for artifact in input_refs.values():
                if isinstance(artifact, dict) and isinstance(artifact.get("artifact_ref"), str):
                    refs.add(artifact["artifact_ref"])
        impact = document.get("source_impact_ref")
        if isinstance(impact, dict) and isinstance(impact.get("artifact_ref"), str):
            refs.add(impact["artifact_ref"])
    return refs


def materialize_artifacts(document: dict, schema: int, source_dir: Path, destination: Path) -> None:
    source_root = source_dir.resolve()
    for raw_ref in sorted(artifact_refs(document, schema)):
        path_text = raw_ref.split("#", 1)[0].strip()
        relative = Path(path_text)
        if not path_text or path_text.startswith(("http://", "https://")) or relative.is_absolute():
            raise ValueError(f"dual-write requires a local relative artifact_ref: {raw_ref}")
        source = (source_root / relative).resolve(strict=True)
        try:
            source.relative_to(source_root)
        except ValueError as exc:
            raise ValueError(f"dual-write artifact escapes input run: {raw_ref}") from exc
        if not source.is_file():
            raise ValueError(f"dual-write artifact is not a file: {raw_ref}")
        write_atomic_bytes(destination / relative, source.read_bytes())


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    project = subparsers.add_parser("project-v3-to-v4")
    project.add_argument("source", type=Path)
    project.add_argument("output", type=Path)
    canonical = subparsers.add_parser("canonicalize")
    canonical.add_argument("source", type=Path)
    canonical.add_argument("output", type=Path)
    compare = subparsers.add_parser("semantic-diff")
    compare.add_argument("left", type=Path)
    compare.add_argument("right", type=Path)
    dual = subparsers.add_parser("dual-write")
    dual.add_argument("v3", type=Path)
    dual.add_argument("v4", type=Path)
    dual.add_argument("output_dir", type=Path)
    dual.add_argument("--v3-artifact-root", type=Path)
    dual.add_argument("--v4-artifact-root", type=Path)
    args = parser.parse_args()

    try:
        if args.command == "project-v3-to-v4":
            projected = v3_to_v4(load_json(args.source), args.source.resolve().parent)
            errors = validate_results_v4(projected, args.source.resolve())
            if errors:
                raise ValueError("invalid projection: " + "; ".join(errors))
            write_atomic(args.output, dump_json(projected))
            print(args.output)
            return 0
        if args.command == "canonicalize":
            write_atomic(args.output, dump_json(canonicalize_results(load_json(args.source))))
            print(args.output)
            return 0
        if args.command == "dual-write":
            v3 = load_json(args.v3)
            v4 = load_json(args.v4)
            if v3.get("schema_version") != 3:
                raise ValueError("dual-write v3 input must use schema_version=3")
            if args.v3.name != "results.json":
                raise ValueError("dual-write v3 input must be named results.json for canonical validation")
            validator = Path(__file__).resolve().parent / "validate-results.sh"
            validation = subprocess.run(
                [str(validator), str(args.v3.resolve())],
                cwd=args.v3.resolve().parent,
                text=True,
                capture_output=True,
                check=False,
            )
            if validation.returncode != 0:
                detail = (validation.stdout + validation.stderr).strip()
                raise ValueError(f"dual-write v3 validation failed: {detail}")
            v3_artifact_root = (args.v3_artifact_root or args.v3.parent).resolve()
            v4_artifact_root = (args.v4_artifact_root or args.v4.parent).resolve()
            v4_errors = validate_results_v4(v4, v4_artifact_root / "results.json")
            if v4_errors:
                raise ValueError("dual-write v4 input is invalid: " + "; ".join(v4_errors))
            compatibility = v4.get("compatibility")
            expected_v3_sha256 = sha256_json(v3)
            if (
                not isinstance(compatibility, dict)
                or compatibility.get("projected_from") != 3
                or compatibility.get("v3_sha256") != expected_v3_sha256
            ):
                raise ValueError("dual-write v4 compatibility does not bind the exact v3 input")
            if compatibility.get("v3_projection_ref") not in {None, "../v3/results.json"}:
                raise ValueError("dual-write v3_projection_ref must target ../v3/results.json")
            differences = semantic_diff(v3, v4)
            if differences:
                raise ValueError("dual-write semantic diff failed: " + "; ".join(differences))
            output_dir = args.output_dir.resolve()
            if output_dir.exists():
                raise ValueError("dual-write output_dir must not exist")
            output_dir.parent.mkdir(parents=True, exist_ok=True)
            staging = Path(
                tempfile.mkdtemp(
                    prefix=f".{output_dir.name}.staging.",
                    dir=str(output_dir.parent),
                )
            )
            published = False
            try:
                v3_dir = staging / "v3"
                v4_dir = staging / "v4"
                materialize_artifacts(v3, 3, v3_artifact_root, v3_dir)
                materialize_artifacts(v4, 4, v4_artifact_root, v4_dir)
                output_v4 = copy.deepcopy(v4)
                output_v4["compatibility"]["v3_projection_ref"] = "../v3/results.json"
                write_atomic(v3_dir / "results.json", dump_json(v3))
                write_atomic(v4_dir / "results.json", dump_json(output_v4))
                output_v4_errors = validate_results_v4(output_v4, v4_dir / "results.json")
                if output_v4_errors:
                    raise ValueError(
                        "materialized v4 is invalid: " + "; ".join(output_v4_errors)
                    )
                write_atomic(
                    staging / "semantic-diff.json",
                    dump_json(
                        {
                            "status": "pass",
                            "differences": [],
                            "v3_sha256": sha256_json(v3),
                            "v4_sha256": sha256_json(output_v4),
                            "v3_projection_ref": "v3/results.json",
                            "v4_result_ref": "v4/results.json",
                            "canonical": canonicalize_results(output_v4),
                        }
                    ),
                )
                os.replace(staging, output_dir)
                published = True
            finally:
                if not published and staging.exists():
                    shutil.rmtree(staging)
            print(json.dumps({"status": "pass", "output_dir": str(args.output_dir)}, sort_keys=True))
            return 0
        differences = semantic_diff(load_json(args.left), load_json(args.right))
    except (OSError, ValueError) as exc:
        print(f"hybrid results operation failed: {exc}", file=sys.stderr)
        return 2
    if differences:
        for difference in differences:
            print(f"- {difference}", file=sys.stderr)
        return 1
    print("semantic diff passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
