#!/usr/bin/env python3
"""Build and validate the single-file Better Test developer report."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


REPORT_MARKER = "<!-- better-test-full-report:v1 -->"
NO_BUGS_TEXT = "本轮无 Bug Report。"
REQUIRED_BUG_SECTIONS = (
    ("TL;DR", r"TL;DR"),
    ("现象矩阵", r"现象矩阵"),
    ("基准对照", r"基准对照"),
    ("其他对照", r"其他对照"),
    ("权限/账号排除", r"权限/账号排除"),
    ("Root cause 推测", r"Root\s+cause\s+推测"),
    ("复现步骤", r"复现步骤"),
    ("影响评估", r"影响评估"),
)


class ReportError(RuntimeError):
    """A deterministic full-report contract violation."""


def canonical_text(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    return text.rstrip() + "\n"


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def choose_required(run_dir: Path, names: tuple[str, ...]) -> Path:
    matches = [run_dir / name for name in names if (run_dir / name).is_file()]
    if not matches:
        raise ReportError(f"缺少必需文件，候选为: {', '.join(names)}")
    return matches[0]


def validate_bug_source(path: Path, text: str) -> None:
    section_matches: list[tuple[str, re.Match[str]]] = []
    for label, pattern in REQUIRED_BUG_SECTIONS:
        matches = list(
            re.finditer(
                rf"(?mi)^##+\s+(?:\d+[.)]?\s*)?{pattern}\s*$",
                text,
            )
        )
        if not matches:
            raise ReportError(f"{path.name} 缺少 Bug Report 必填章节: {label}")
        if len(matches) > 1:
            raise ReportError(f"{path.name} 重复 Bug Report 必填章节: {label}")
        section_matches.append((label, matches[0]))
    if [match.start() for _, match in section_matches] != sorted(
        match.start() for _, match in section_matches
    ):
        raise ReportError(f"{path.name} 的 Bug Report 必填章节顺序错误")

    metadata_match = re.search(r"(?m)^\s*bug:\s*$", text)
    if metadata_match is None:
        raise ReportError(f"{path.name} 缺少结构化 bug 元数据块")
    for index, (label, match) in enumerate(section_matches):
        next_start = (
            section_matches[index + 1][1].start()
            if index + 1 < len(section_matches)
            else metadata_match.start()
        )
        body = text[match.end():next_start]
        body_without_fences = re.sub(
            r"(?m)^```(?:ya?ml)?\s*$",
            "",
            body,
        ).strip()
        if not body_without_fences:
            raise ReportError(f"{path.name} 必填章节没有正文: {label}")
    for field in (
        "id",
        "title",
        "status",
        "severity",
        "evidence_level",
        "evidence_refs",
        "bug_type",
        "affected_groups",
        "affected_scenarios",
        "found_in",
        "found_by_tester",
        "found_by_run",
        "related_tests",
        "version_found",
        "version_fixed",
        "regression_canary",
        "post_ship",
        "escape_id",
    ):
        if re.search(rf"(?m)^\s+{re.escape(field)}:\s*\S", text) is None:
            raise ReportError(f"{path.name} 缺少 bug 元数据字段: {field}")


def collect_bug_ids(value: Any) -> set[str]:
    found: set[str] = set()
    if isinstance(value, dict):
        for key, child in value.items():
            if key == "bug_ids" and isinstance(child, list):
                found.update(
                    item.strip()
                    for item in child
                    if isinstance(item, str) and item.strip()
                )
            elif key == "bug_id" and isinstance(child, str) and child.strip():
                found.add(child.strip())
            else:
                found.update(collect_bug_ids(child))
    elif isinstance(value, list):
        for child in value:
            found.update(collect_bug_ids(child))
    return found


def load_sources(run_dir: Path) -> dict[str, Any]:
    summary_path = choose_required(
        run_dir, ("merged-summary.md", "summary.md")
    )
    results_path = choose_required(
        run_dir, ("merged-results.json", "results.json")
    )
    try:
        results_data = json.loads(results_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ReportError(f"{results_path.name} 不是合法 JSON: {exc}") from exc

    bugs_dir = run_dir / "bugs"
    bug_paths = (
        sorted(
            path
            for path in bugs_dir.glob("BUG-*.md")
            if path.is_file() and not path.is_symlink()
        )
        if bugs_dir.is_dir()
        else []
    )
    bug_texts: dict[Path, str] = {}
    for path in bug_paths:
        text = canonical_text(path)
        validate_bug_source(path, text)
        bug_texts[path] = text

    referenced_ids = collect_bug_ids(results_data)
    for bug_id in sorted(referenced_ids):
        if not any(
            re.search(
                rf"(?mi)(?:^#.*\b|^\s*id:\s*){re.escape(bug_id)}\b",
                text,
            )
            for text in bug_texts.values()
        ):
            raise ReportError(
                f"results 引用了 {bug_id}，但 bugs/ 中没有对应完整 Bug Report"
            )

    optional_names = (
        "status.md",
        "audit-report.md",
        "l2-findings.md",
        "conflict-log.md",
        "verdict-challenge.md",
    )
    optional_paths = [
        run_dir / name for name in optional_names if (run_dir / name).is_file()
    ]
    return {
        "summary_path": summary_path,
        "summary_text": canonical_text(summary_path),
        "results_path": results_path,
        "results_text": canonical_text(results_path),
        "bug_texts": bug_texts,
        "optional_paths": optional_paths,
    }


def source_block(kind: str, path: Path, text: str) -> str:
    digest = sha256_text(text)
    return (
        f"<!-- {kind}-BEGIN file={path.name} sha256={digest} -->\n"
        f"{text}"
        f"<!-- {kind}-END file={path.name} -->\n"
    )


def build_report(run_dir: Path, sources: dict[str, Any]) -> str:
    generated = datetime.now().astimezone().isoformat(timespec="seconds")
    parts = [
        f"# 完整测试报告 — {run_dir.name}\n\n",
        f"> Generated: {generated}\n",
        "> Developer deliverable: single self-contained file\n\n",
        f"{REPORT_MARKER}\n\n",
        "## 测试结论\n\n",
        source_block(
            "SUMMARY",
            sources["summary_path"],
            sources["summary_text"],
        ),
    ]

    for path in sources["optional_paths"]:
        text = canonical_text(path)
        parts.extend(
            [
                f"\n## 附加审计材料 — {path.name}\n\n",
                source_block("SUPPORT", path, text),
            ]
        )

    parts.append("\n## 完整 Bug Reports\n\n")
    bug_texts: dict[Path, str] = sources["bug_texts"]
    if not bug_texts:
        parts.append(f"{NO_BUGS_TEXT}\n")
    else:
        for index, (path, text) in enumerate(bug_texts.items(), start=1):
            parts.extend(
                [
                    f"\n### Bug Report {index}/{len(bug_texts)} — {path.name}\n\n",
                    source_block("BUG-REPORT", path, text),
                ]
            )

    results_path: Path = sources["results_path"]
    results_text: str = sources["results_text"]
    parts.extend(
        [
            "\n## 完整机器结果\n\n",
            source_block("RESULTS", results_path, results_text),
            "\n",
        ]
    )
    return "".join(parts)


def require_exact_block(
    report: str, kind: str, path: Path, expected: str
) -> None:
    digest = sha256_text(expected)
    begin = f"<!-- {kind}-BEGIN file={path.name} sha256={digest} -->\n"
    end = f"<!-- {kind}-END file={path.name} -->"
    start = report.find(begin)
    if start < 0:
        raise ReportError(f"主报告缺少 {path.name} 的完整嵌入标记")
    start += len(begin)
    finish = report.find(end, start)
    if finish < 0:
        raise ReportError(f"主报告缺少 {path.name} 的结束标记")
    embedded = report[start:finish]
    if embedded != expected:
        raise ReportError(f"{path.name} 在主报告中的完整正文不一致")
    if report.find(begin, start) >= 0:
        raise ReportError(f"{path.name} 在主报告中重复嵌入")


def validate_report(
    report_path: Path, sources: dict[str, Any]
) -> None:
    if not report_path.is_file():
        raise ReportError(f"主报告不存在: {report_path}")
    report = report_path.read_text(encoding="utf-8")
    if REPORT_MARKER not in report:
        raise ReportError("主报告缺少 better-test full-report 标记")
    require_exact_block(
        report,
        "SUMMARY",
        sources["summary_path"],
        sources["summary_text"],
    )
    for path in sources["optional_paths"]:
        require_exact_block(
            report,
            "SUPPORT",
            path,
            canonical_text(path),
        )
    bug_texts: dict[Path, str] = sources["bug_texts"]
    if bug_texts:
        for path, text in bug_texts.items():
            require_exact_block(report, "BUG-REPORT", path, text)
        marker_count = report.count("<!-- BUG-REPORT-BEGIN ")
        if marker_count != len(bug_texts):
            raise ReportError(
                "主报告 Bug Report 数量与 bugs/ 源文件数量不一致"
            )
    elif NO_BUGS_TEXT not in report:
        raise ReportError("无 bug 时主报告必须显式写明本轮无 Bug Report")
    require_exact_block(
        report,
        "RESULTS",
        sources["results_path"],
        sources["results_text"],
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Build one self-contained developer report containing every "
            "complete Bug Report and the full machine result ledger."
        )
    )
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--validate-only", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    run_dir = args.run_dir.resolve()
    if not run_dir.is_dir():
        raise ReportError(f"run/merge 目录不存在: {run_dir}")
    output = (
        args.output.resolve()
        if args.output is not None
        else run_dir / "FULL-TEST-REPORT.md"
    )
    sources = load_sources(run_dir)
    if not args.validate_only:
        output.write_text(build_report(run_dir, sources), encoding="utf-8")
    validate_report(output, sources)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ReportError) as exc:
        print(f"[full-report] FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
