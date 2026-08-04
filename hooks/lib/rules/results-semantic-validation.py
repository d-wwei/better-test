#!/usr/bin/env python3
"""Checks that are awkward or unsafe to express in jq alone."""

from __future__ import annotations

import json
import hashlib
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

        hybrid = document.get("hybrid")
        if hybrid is not None:
            if not isinstance(hybrid, dict):
                errors.append("- schema v3.1 hybrid 必须是对象")
            else:
                if hybrid.get("contract_version") != "1.0.0":
                    errors.append("- schema v3.1 hybrid.contract_version 必须是 1.0.0")
                if hybrid.get("mode") not in {"blackbox", "whitebox", "hybrid"}:
                    errors.append("- schema v3.1 hybrid.mode 不支持")
                for field in ("objective", "max_claim_scope"):
                    value = hybrid.get(field)
                    if not isinstance(value, str) or not value.strip() or value != value.strip():
                        errors.append(f"- schema v3.1 hybrid.{field} 必须是非空字符串")
                missing = hybrid.get("missing_capabilities")
                if not isinstance(missing, list) or not all(
                    isinstance(value, str) and value.strip() and value == value.strip()
                    for value in missing
                ):
                    errors.append("- schema v3.1 hybrid.missing_capabilities 必须是字符串数组")
                semantic_diff = hybrid.get("semantic_diff")
                if semantic_diff not in {"pass", "fail", "not_run"}:
                    errors.append("- schema v3.1 hybrid.semantic_diff 不支持")
                artifacts = hybrid.get("artifacts")
                if not isinstance(artifacts, dict):
                    errors.append("- schema v3.1 hybrid.artifacts 必须是对象")
                else:
                    for name, artifact in artifacts.items():
                        if not isinstance(artifact, dict):
                            errors.append(f"- schema v3.1 hybrid.artifacts.{name} 必须是对象")
                            continue
                        artifact_ref = artifact.get("artifact_ref")
                        expected_sha = artifact.get("sha256")
                        if not isinstance(artifact_ref, str) or not artifact_ref.strip():
                            errors.append(f"- schema v3.1 hybrid.artifacts.{name}.artifact_ref 缺失")
                            continue
                        if not isinstance(expected_sha, str) or len(expected_sha) != 64 or any(
                            char not in "0123456789abcdef" for char in expected_sha
                        ):
                            errors.append(f"- schema v3.1 hybrid.artifacts.{name}.sha256 无效")
                            continue
                        path_text = artifact_ref.split("#", 1)[0].strip()
                        if path_text.startswith(("http://", "https://")):
                            errors.append(f"- schema v3.1 hybrid.artifacts.{name} 必须归档为本地 artifact")
                            continue
                        artifact_path = Path(path_text)
                        if not artifact_path.is_absolute():
                            artifact_path = run_dir / artifact_path
                        try:
                            artifact_path = artifact_path.resolve(strict=True)
                            artifact_path.relative_to(run_dir)
                        except (OSError, ValueError):
                            errors.append(f"- schema v3.1 hybrid.artifacts.{name} 不存在或超出 run 目录")
                            continue
                        digest = hashlib.sha256(artifact_path.read_bytes()).hexdigest()
                        if digest != expected_sha:
                            errors.append(f"- schema v3.1 hybrid.artifacts.{name} sha256 不匹配")

    if errors:
        print("\n".join(errors))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
