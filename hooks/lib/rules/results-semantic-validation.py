#!/usr/bin/env python3
"""Checks that are awkward or unsafe to express in jq alone."""

from __future__ import annotations

import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


def reject_constant(value: str) -> None:
    raise ValueError(f"non-standard JSON constant: {value}")


def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def parse_timestamp(value: Any, field: str, errors: list[str]) -> datetime | None:
    if not isinstance(value, str) or not value.strip() or value != value.strip():
        errors.append(f"- schema v3 {field} 必须是无首尾空白且带时区的 ISO 8601 时间")
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        errors.append(f"- schema v3 {field} 不是有效的 ISO 8601 日期时间")
        return None
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        errors.append(f"- schema v3 {field} 必须包含时区")
        return None
    return parsed


def main() -> int:
    try:
        document = json.load(
            sys.stdin,
            parse_constant=reject_constant,
            object_pairs_hook=reject_duplicate_keys,
        )
    except (json.JSONDecodeError, ValueError) as exc:
        print(f"- JSON 严格解析失败: {exc}")
        return 0

    if not isinstance(document, dict) or document.get("schema_version") != 3:
        return 0

    errors: list[str] = []
    results_path = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else None
    if type(document.get("schema_version")) is not int:
        errors.append("- schema_version 必须是整数 3，不能写成浮点数")
    for field in ("version", "tester_id", "run_id", "mode"):
        value = document.get(field)
        if (
            not isinstance(value, str)
            or not value.strip()
            or value != value.strip()
        ):
            errors.append(
                f"- schema v3 顶层字段 {field} 必须是无首尾空白的非空字符串"
            )

    started = parse_timestamp(document.get("started_at"), "started_at", errors)
    finished = parse_timestamp(document.get("finished_at"), "finished_at", errors)
    if started is not None and finished is not None and finished < started:
        errors.append("- schema v3 finished_at 不得早于 started_at")

    readiness = document.get("release_readiness")
    override = readiness.get("override") if isinstance(readiness, dict) else None
    if isinstance(override, dict):
        for field in ("approved_by", "reason"):
            value = override.get(field)
            if (
                not isinstance(value, str)
                or not value.strip()
                or value != value.strip()
            ):
                errors.append(
                    "- schema v3 release_readiness.override."
                    f"{field} 必须是无首尾空白的非空字符串"
                )
        approved = parse_timestamp(
            override.get("approved_at"),
            "release_readiness.override.approved_at",
            errors,
        )
        if (
            approved is not None
            and finished is not None
            and approved < finished
        ):
            errors.append(
                "- schema v3 release_readiness.override.approved_at "
                "不得早于 finished_at"
            )

    if results_path is None:
        errors.append("- schema v3 evidence artifact 校验缺少 results.json 路径")
    else:
        run_dir = results_path.parent.resolve()
        for item in document.get("items", []):
            if not isinstance(item, dict):
                continue
            item_id = item.get("id", "<missing-id>")
            sources = item.get("evidence_sources")
            if not isinstance(sources, list):
                continue
            resolved_artifacts: set[Path] = set()
            resolved_by_source: dict[str, Path] = {}
            for source in sources:
                if not isinstance(source, dict):
                    continue
                source_id = source.get("source_id", "<missing-source-id>")
                artifact_ref = source.get("artifact_ref")
                if not isinstance(artifact_ref, str) or not artifact_ref.strip():
                    continue
                path_text = artifact_ref.split("#", 1)[0].strip()
                if path_text.startswith(("http://", "https://")):
                    errors.append(
                        f"- schema v3 item {item_id} evidence {source_id} "
                        "必须归档为本地 artifact；远程 URL 不能形成可复核证据"
                    )
                    continue
                artifact_path = Path(path_text)
                if not artifact_path.is_absolute():
                    artifact_path = run_dir / artifact_path
                try:
                    artifact_path = artifact_path.resolve(strict=True)
                except OSError:
                    errors.append(
                        f"- schema v3 item {item_id} evidence {source_id} "
                        f"artifact 文件不存在: {artifact_ref}"
                    )
                    continue
                if not artifact_path.is_file():
                    errors.append(
                        f"- schema v3 item {item_id} evidence {source_id} "
                        f"artifact 不是文件: {artifact_ref}"
                    )
                    continue
                try:
                    artifact_path.relative_to(run_dir)
                except ValueError:
                    errors.append(
                        f"- schema v3 item {item_id} evidence {source_id} "
                        f"artifact 必须位于本 run 目录内: {artifact_ref}"
                    )
                    continue
                resolved_artifacts.add(artifact_path)
                if isinstance(source_id, str):
                    resolved_by_source[source_id] = artifact_path
            if (
                str(item.get("evidence_level", "")).strip().lower()
                == "confirmed"
                and len(resolved_artifacts) < 2
            ):
                errors.append(
                    f"- schema v3 confirmed item {item_id} 需要至少两个"
                    "不同的本地 artifact 文件；同一文件的不同 fragment 不算独立"
                )
            proven_basis = item.get("proven_basis")
            if (
                str(item.get("evidence_level", "")).strip().lower() == "proven"
                and isinstance(proven_basis, dict)
            ):
                basis_refs = proven_basis.get("evidence_refs")
                basis_files = {
                    resolved_by_source[source_id]
                    for source_id in (
                        basis_refs if isinstance(basis_refs, list) else []
                    )
                    if isinstance(source_id, str)
                    and source_id in resolved_by_source
                }
                if (
                    proven_basis.get("kind") == "multi-version"
                    and len(basis_files) < 2
                ):
                    errors.append(
                        f"- schema v3 proven item {item_id} 的 multi-version "
                        "basis 需要至少两个不同的本地 artifact 文件"
                    )
                if str(item.get("type", "")).strip().lower() == "functional":
                    runtime_refs = proven_basis.get("runtime_evidence_refs")
                    runtime_files = {
                        resolved_by_source[source_id]
                        for source_id in (
                            runtime_refs
                            if isinstance(runtime_refs, list)
                            else []
                        )
                        if isinstance(source_id, str)
                        and source_id in resolved_by_source
                    }
                    if not (runtime_files - basis_files):
                        errors.append(
                            f"- schema v3 proven functional item {item_id} "
                            "至少需要一个与 proven basis 文件不同的 runtime artifact"
                        )

    if errors:
        print("\n".join(errors))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
