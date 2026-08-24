#!/usr/bin/env python3
"""Build a static pytest reference-suite map without importing the suite."""

from __future__ import annotations

import argparse
import ast
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
from typing import Any, Iterable


WRITE_CALLS = {
    "modify_user_security",
    "set_price_reminder",
    "set_option_event_alert",
}
TRADE_WRITE_CALLS = {
    "unlock_trade",
    "place_order",
    "place_combo_order",
    "modify_order",
    "cancel_all_order",
    "reconfirm_order",
}
DESTRUCTIVE_CALLS = {
    "cancel_all_order",
    "delete",
    "remove",
    "unlink",
    "kill",
    "terminate",
}
NOISE_CALLS = {
    "append",
    "astype",
    "close",
    "copy",
    "debug",
    "error",
    "fail",
    "fixture",
    "format",
    "get",
    "getLogger",
    "info",
    "isna",
    "items",
    "keys",
    "len",
    "lower",
    "mark",
    "notna",
    "param",
    "parametrize",
    "skip",
    "sleep",
    "sort",
    "sorted",
    "startswith",
    "strip",
    "tolist",
    "upper",
    "values",
    "warning",
}
MARKER_ENVIRONMENTS = {
    "hk_stock": "market:HK",
    "hk_etf": "market:HK",
    "hk_future": "market:HK_FUTURES",
    "hk_option": "market:HK_OPTIONS",
    "us_stock": "market:US",
    "us_etf": "market:US",
    "us_future": "market:US_FUTURES",
    "us_option": "market:US_OPTIONS",
    "us_index": "market:US_INDEX",
    "cn_stock": "market:CN",
    "sg_stock": "market:SG",
    "sg_future": "market:SG_FUTURES",
    "jp_stock": "market:JP",
    "jp_future": "market:JP_FUTURES",
    "my_stock": "market:MY",
    "au_stock": "market:AU",
    "ca_stock": "market:CA",
    "kr_stock": "market:KR",
    "ec": "capability:event_contract",
}
DANGER_PATTERNS = (
    ("credential_config", "high", re.compile(r"\b(login_pwd|unlock_trade_pwd|password|pwd)\b")),
    ("process_launch", "warning", re.compile(r"\b(subprocess\.Popen|os\.system|create_subprocess)")),
    ("process_kill", "high", re.compile(r"\.(kill|terminate)\(")),
    ("autouse_fixture", "warning", re.compile(r"pytest\.fixture\([^)]*autouse\s*=\s*True")),
    ("real_trade", "high", re.compile(r"\.(unlock_trade|place_order|place_combo_order|modify_order|cancel_all_order)\(")),
    ("external_write", "warning", re.compile(r"\.(modify_user_security|set_price_reminder|set_option_event_alert)\(")),
    ("random_input", "warning", re.compile(r"\brandom\.(choice|sample|shuffle|randint|random)\(")),
    ("fixed_sleep", "warning", re.compile(r"\btime\.sleep\(")),
    ("skip_on_runtime", "warning", re.compile(r"\bpytest\.skip\(")),
)


def git(repo: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(repo), *args],
        text=True,
        stderr=subprocess.DEVNULL,
    ).strip()


def marker_name(node: ast.AST) -> str | None:
    value = node
    if isinstance(value, ast.Call):
        value = value.func
    names: list[str] = []
    while isinstance(value, ast.Attribute):
        names.append(value.attr)
        value = value.value
    if isinstance(value, ast.Name):
        names.append(value.id)
    names.reverse()
    if len(names) >= 3 and names[:2] == ["pytest", "mark"]:
        return names[2]
    return None


def marker_names(decorators: Iterable[ast.expr]) -> set[str]:
    return {name for node in decorators if (name := marker_name(node))}


def module_markers(tree: ast.Module) -> set[str]:
    result: set[str] = set()
    for node in tree.body:
        if not isinstance(node, (ast.Assign, ast.AnnAssign)):
            continue
        targets = node.targets if isinstance(node, ast.Assign) else [node.target]
        if not any(isinstance(target, ast.Name) and target.id == "pytestmark" for target in targets):
            continue
        value = node.value
        values = value.elts if isinstance(value, (ast.List, ast.Tuple, ast.Set)) else [value]
        result.update(marker_names(values))
    return result


def direct_call_names(node: ast.AST) -> set[str]:
    result: set[str] = set()
    for child in ast.walk(node):
        if not isinstance(child, ast.Call):
            continue
        func = child.func
        if isinstance(func, ast.Attribute):
            name = func.attr
        elif isinstance(func, ast.Name):
            name = func.id
        else:
            continue
        if name not in NOISE_CALLS:
            result.add(name)
    return result


def expanded_call_names(
    initial: set[str],
    definitions: dict[str, set[str]],
) -> set[str]:
    expanded: set[str] = set()
    pending = list(initial)
    visited_helpers: set[str] = set()
    while pending:
        name = pending.pop()
        if name in definitions:
            if name in visited_helpers:
                continue
            visited_helpers.add(name)
            pending.extend(definitions[name])
            continue
        if not name.startswith("_"):
            expanded.add(name)
    return expanded


def skip_categories(node: ast.AST) -> set[str]:
    categories: set[str] = set()
    for child in ast.walk(node):
        if not isinstance(child, ast.Call):
            continue
        if not (
            isinstance(child.func, ast.Attribute)
            and isinstance(child.func.value, ast.Name)
            and child.func.value.id == "pytest"
            and child.func.attr == "skip"
        ):
            continue
        text = ast.unparse(child.args[0]).lower() if child.args else ""
        if "权限" in text or "permission" in text or "entitlement" in text:
            categories.add("missing_entitlement")
        elif "账户" in text or "account" in text:
            categories.add("missing_account")
        elif (
            "盘中" in text
            or "交易时段" in text
            or "无首推" in text
            or "market closed" in text
        ):
            categories.add("market_closed")
        elif (
            "限频" in text
            or "超时" in text
            or "额度" in text
            or "rate" in text
            or "quota" in text
        ):
            categories.add("rate_limited")
        elif "未实现" in text or "not implemented" in text:
            categories.add("upstream_not_implemented")
        elif (
            "设置环境变量" in text
            or "跳过真实" in text
            or "approval" in text
            or "授权" in text
        ):
            categories.add("unsafe_without_approval")
        elif "服务端未支持" in text or "not supported" in text:
            categories.add("missing_capability")
        elif any(
            token in text
            for token in (
                "无数据",
                "为空",
                "不足",
                "无有效",
                "无排行",
                "无组合",
                "无持仓",
                "无订单",
                "无成交",
                "无可用",
                "未取到",
                "未找到",
                "全为",
                "无未来",
                "无未到期",
                "无法选出",
                "无法对比",
                "无法校验",
                "无法测分页",
                "无需分页",
                "未返回 next",
                "无 page_req_key",
                "明细为空",
                "总量不足",
                "已在明细",
                "到期日解析为空",
            )
        ):
            categories.add("data_unavailable")
        elif (
            "不可改单" in text
            or "order_status" in text
            or "product behavior" in text
        ):
            categories.add("product_behavior")
        else:
            categories.add("fixture_failure")
    return categories


def side_effect_for(calls: set[str]) -> tuple[str, str]:
    if calls & DESTRUCTIVE_CALLS:
        return "destructive", "L4"
    if calls & TRADE_WRITE_CALLS:
        return "write", "L4"
    if calls & WRITE_CALLS:
        return "write", "L3"
    if calls:
        return "read", "L1"
    return "none", "L0"


def slug(value: str) -> str:
    return re.sub(r"[^A-Z0-9]+", "-", value.upper()).strip("-")


def infer_target_id(relative_file: str, class_name: str, function_name: str) -> str:
    parts = Path(relative_file).parts
    domain = "-".join(parts[1:-1]) if len(parts) > 2 else parts[0]
    return "OFFICIAL-" + slug(f"{domain}-{Path(relative_file).stem}-{class_name}-{function_name}")


def parse_surface_manifest(path: Path | None) -> set[str]:
    if path is None:
        return set()
    data = json.loads(path.read_text(encoding="utf-8"))
    values = data.get("endpoint_ids", [])
    return {str(value).lower().replace("-", "_") for value in values}


def build_cases(repo: Path, roots: list[str], surface_ids: set[str]) -> tuple[list[dict[str, Any]], set[str]]:
    cases: list[dict[str, Any]] = []
    files: set[str] = set()
    for root_name in roots:
        root = repo / root_name
        if not root.exists():
            continue
        for path in sorted(root.rglob("test_*.py")):
            relative = path.relative_to(repo).as_posix()
            source = path.read_text(encoding="utf-8")
            tree = ast.parse(source, filename=relative)
            file_hash = hashlib.sha256(source.encode("utf-8")).hexdigest()
            inherited_module_markers = module_markers(tree)
            definitions = {
                node.name: direct_call_names(node)
                for node in ast.walk(tree)
                if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
            }
            parents: dict[ast.AST, ast.AST] = {}
            for parent in ast.walk(tree):
                for child in ast.iter_child_nodes(parent):
                    parents[child] = parent
            for node in ast.walk(tree):
                if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    continue
                if not node.name.startswith("test_"):
                    continue
                parent = parents.get(node)
                class_node = parent if isinstance(parent, ast.ClassDef) else None
                class_name = class_node.name if class_node else ""
                markers = set(inherited_module_markers)
                markers.update(marker_names(node.decorator_list))
                if class_node:
                    markers.update(marker_names(class_node.decorator_list))
                fixtures = {
                    arg.arg
                    for arg in (
                        list(node.args.posonlyargs)
                        + list(node.args.args)
                        + list(node.args.kwonlyargs)
                    )
                    if arg.arg not in {"self", "cls"}
                }
                initial_calls = direct_call_names(node)
                for fixture in fixtures:
                    initial_calls.update(definitions.get(fixture, set()))
                calls = expanded_call_names(initial_calls, definitions)
                side_effect, execution_level = side_effect_for(calls)
                stem = path.stem.removeprefix("test_").lower()
                matching_surface = stem in surface_ids or bool(calls & surface_ids)
                status = "adapted" if matching_surface or not surface_ids else "oracle-only"
                environment = {"pytest"}
                if calls:
                    environment.add("opend")
                environment.update(
                    MARKER_ENVIRONMENTS[marker]
                    for marker in markers
                    if marker in MARKER_ENVIRONMENTS
                )
                case_id = f"{relative}::{class_name + '::' if class_name else ''}{node.name}"
                cases.append(
                    {
                        "id": case_id,
                        "file": relative,
                        "class": class_name,
                        "function": node.name,
                        "markers": sorted(markers),
                        "fixtures": sorted(fixtures),
                        "call_names": sorted(calls),
                        "side_effect": side_effect,
                        "execution_level": execution_level,
                        "adoption_status": status,
                        "target_test_ids": [
                            infer_target_id(relative, class_name, node.name)
                        ],
                        "oracle_type": "reference_implementation",
                        "environment": sorted(environment),
                        "skip_categories": sorted(skip_categories(node)),
                        "evidence_boundary": (
                            "Source-derived scenario only; runtime claims require "
                            "adapter execution against an identified subject."
                        ),
                        "source_hash": file_hash,
                    }
                )
                files.add(relative)
    return cases, files


def scan_dangers(repo: Path, roots: list[str]) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    candidate_paths: set[Path] = set()
    for root_name in roots:
        root = repo / root_name
        if root.exists():
            candidate_paths.update(root.rglob("*.py"))
    for extra in ("conftest.py", "config/default.yaml", "pytest.ini", "pyproject.toml"):
        path = repo / extra
        if path.exists():
            candidate_paths.add(path)
    for path in sorted(candidate_paths):
        relative = path.relative_to(repo).as_posix()
        for line_number, line in enumerate(
            path.read_text(encoding="utf-8", errors="ignore").splitlines(), 1
        ):
            for kind, severity, pattern in DANGER_PATTERNS:
                if not pattern.search(line):
                    continue
                finding_id = f"DANGER-{len(findings) + 1:04d}"
                findings.append(
                    {
                        "id": finding_id,
                        "kind": kind,
                        "severity": severity,
                        "path": relative,
                        "line": line_number,
                        "message": {
                            "credential_config": "Credential-related configuration requires redaction and external secret handling.",
                            "process_launch": "Suite can launch an external process.",
                            "process_kill": "Suite can terminate a process.",
                            "autouse_fixture": "Autouse fixture may execute before an explicit case selection.",
                            "real_trade": "Suite contains a real-trading or unlock call.",
                            "external_write": "Suite mutates remote user or account state.",
                            "random_input": "Random input requires a recorded seed and candidate pool.",
                            "fixed_sleep": "Fixed sleep requires an explicit calibrated observation window.",
                            "skip_on_runtime": "Runtime skip requires a typed reason and denominator accounting.",
                        }[kind],
                    }
                )
    return findings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--suite-id", required=True)
    parser.add_argument("--repo-url")
    parser.add_argument("--branch")
    parser.add_argument("--commit")
    parser.add_argument("--test-root", action="append", dest="test_roots")
    parser.add_argument("--surface-manifest", type=Path)
    parser.add_argument("--generated-at")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    repo = args.repo.resolve()
    roots = args.test_roots or ["testcases", "tests"]
    repo_url = args.repo_url or git(repo, "remote", "get-url", "origin")
    branch = args.branch or git(repo, "rev-parse", "--abbrev-ref", "HEAD")
    commit = args.commit or git(repo, "rev-parse", "HEAD")
    dirty = bool(git(repo, "status", "--porcelain"))
    generated_at = args.generated_at or datetime.now(timezone.utc).isoformat()
    surface_ids = parse_surface_manifest(args.surface_manifest)
    cases, files = build_cases(repo, roots, surface_ids)
    side_effects = Counter(case["side_effect"] for case in cases)
    statuses = Counter(case["adoption_status"] for case in cases)
    document = {
        "schema_version": 1,
        "generated_at": generated_at,
        "suite": {
            "id": args.suite_id,
            "repo_url": repo_url,
            "branch": branch,
            "commit": commit,
            "dirty": dirty,
        },
        "summary": {
            "files": len(files),
            "static_tests": len(cases),
            "cases": len(cases),
            "side_effects": dict(sorted(side_effects.items())),
            "adoption_statuses": dict(sorted(statuses.items())),
        },
        "danger_scan": {
            "completed": True,
            "findings": scan_dangers(repo, roots),
        },
        "cases": cases,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(document, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        f"built reference suite map: {len(cases)} cases from {len(files)} files "
        f"at {args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
