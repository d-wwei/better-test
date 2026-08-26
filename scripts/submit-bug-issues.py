#!/usr/bin/env python3
"""Validate Better Test bug reports and submit one GitHub issue per bug."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from contextlib import contextmanager, nullcontext
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

try:
    import fcntl
except ImportError:  # pragma: no cover - the existing validators require POSIX shell.
    fcntl = None


EVIDENCE_RANK = {
    "indirect": 0,
    "direct": 1,
    "binary": 1,
    "confirmed": 2,
    "proven": 3,
}
DEFAULT_REPORT_NAMES = ("FULL-TEST-REPORT.md", "FULL-TEST-REPORT-CN.md")
DEFAULT_LEDGER_NAME = "bug-issue-submissions.json"
DEFAULT_BODY_PREAMBLE = (
    "Submitted from a machine-validated Better Test Bug Report. "
    "Local evidence remains in the test run; this issue contains the "
    "complete sanitized report."
)
MARKER_PREFIX = "better-test-bug-fingerprint"
SOURCE_RUN_PREFIX = "better-test-source-run"
SUBMISSION_KEY_PREFIX = "better-test-submission-key"


class SubmissionError(RuntimeError):
    """A deterministic issue-submission contract violation."""


@dataclass(frozen=True)
class Candidate:
    path: Path
    text: str
    metadata: dict[str, Any]
    bug_id: str
    title: str
    source_run: str
    version_found: str
    submission_key: str
    evidence_level: str
    fingerprint: str
    issue_title: str
    issue_body: str


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def canonical_text(path: Path) -> str:
    return path.read_text(encoding="utf-8").rstrip() + "\n"


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SubmissionError(f"invalid JSON in {path}: {exc}") from exc


def atomic_write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(temp_name, path)
    except Exception:
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass
        raise


@contextmanager
def submission_lock(repository: str):
    digest = sha256_text(repository.lower())[:20]
    path = Path(tempfile.gettempdir()) / f"better-test-issue-{digest}.lock"
    with path.open("a+", encoding="utf-8") as handle:
        if fcntl is not None:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            if fcntl is not None:
                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def run_command(
    command: list[str], *, input_text: str | None = None
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command,
        input=input_text,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise SubmissionError(
            f"command failed ({result.returncode}): {' '.join(command)}"
            + (f"\n{detail}" if detail else "")
        )
    return result


def parse_scalar(raw: str) -> Any:
    value = raw.strip()
    if not value:
        return ""
    if value in {"null", "Null", "NULL", "~"}:
        return None
    if value.lower() == "true":
        return True
    if value.lower() == "false":
        return False
    if (
        len(value) >= 2
        and value[0] == value[-1]
        and value[0] in {'"', "'"}
    ):
        return value[1:-1]
    if value.startswith("[") and value.endswith("]"):
        body = value[1:-1].strip()
        if not body:
            return []
        return [parse_scalar(part) for part in body.split(",")]
    return value


def extract_bug_metadata(text: str, path: Path) -> dict[str, Any]:
    blocks = re.findall(
        r"(?ms)^```ya?ml\s*\n(?P<body>.*?)^\s*```\s*$", text
    )
    for block in reversed(blocks):
        lines = block.splitlines()
        bug_index = next(
            (
                index
                for index, line in enumerate(lines)
                if re.fullmatch(r"\s*bug:\s*", line)
            ),
            None,
        )
        if bug_index is None:
            continue
        metadata: dict[str, Any] = {}
        for line in lines[bug_index + 1 :]:
            if not line.strip():
                continue
            match = re.match(r"^\s{2}([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$", line)
            if match:
                metadata[match.group(1)] = parse_scalar(match.group(2))
                continue
            if re.match(r"^\S", line):
                break
        if metadata:
            return metadata
    raise SubmissionError(f"{path.name} has no parseable fenced YAML bug block")


def require_string(
    metadata: dict[str, Any], field: str, path: Path
) -> str:
    value = metadata.get(field)
    if not isinstance(value, str) or not value.strip():
        raise SubmissionError(f"{path.name} missing non-empty bug.{field}")
    return value.strip()


def load_policy(path: Path) -> dict[str, Any]:
    policy = load_json(path)
    if not isinstance(policy, dict):
        raise SubmissionError("issue policy must be a JSON object")
    required = {
        "schema_version",
        "provider",
        "repository",
        "enabled",
        "eligible_statuses",
        "eligible_evidence_levels",
        "labels",
        "require_submission_key",
        "require_full_report",
        "require_results_validation",
        "title_template",
    }
    missing = sorted(required - policy.keys())
    if missing:
        raise SubmissionError(
            f"issue policy missing fields: {', '.join(missing)}"
        )
    if policy["schema_version"] != 1:
        raise SubmissionError("issue policy schema_version must be 1")
    if policy["provider"] != "github":
        raise SubmissionError("only provider=github is supported")
    for field in (
        "enabled",
        "require_submission_key",
        "require_full_report",
        "require_results_validation",
    ):
        if not isinstance(policy[field], bool):
            raise SubmissionError(f"issue policy {field} must be boolean")
    repository = policy["repository"]
    if not isinstance(repository, str) or not re.fullmatch(
        r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository
    ):
        raise SubmissionError("issue policy repository must be owner/name")
    for field in ("eligible_statuses", "eligible_evidence_levels", "labels"):
        value = policy[field]
        if not isinstance(value, list) or not all(
            isinstance(item, str) and item.strip() for item in value
        ):
            raise SubmissionError(f"issue policy {field} must be string[]")
    levels = {level.lower() for level in policy["eligible_evidence_levels"]}
    if not levels or not levels <= {"confirmed", "proven"}:
        raise SubmissionError(
            "eligible_evidence_levels may contain only confirmed/proven"
        )
    statuses = {status.upper() for status in policy["eligible_statuses"]}
    if not statuses or not statuses <= {"OPEN", "CONFIRMED"}:
        raise SubmissionError(
            "eligible_statuses may contain only OPEN/CONFIRMED"
        )
    if (
        not isinstance(policy["title_template"], str)
        or not policy["title_template"].strip()
    ):
        raise SubmissionError(
            "issue policy title_template must be a non-empty string"
        )
    body_preamble = policy.get("body_preamble")
    if body_preamble is not None and (
        not isinstance(body_preamble, str) or not body_preamble.strip()
    ):
        raise SubmissionError(
            "issue policy body_preamble must be a non-empty string"
        )
    return policy


def choose_file(run_dir: Path, names: tuple[str, ...]) -> Path:
    for name in names:
        path = run_dir / name
        if path.is_file():
            return path
    raise SubmissionError(
        f"missing required file under {run_dir}: {', '.join(names)}"
    )


def validate_full_report(run_dir: Path, policy: dict[str, Any]) -> Path | None:
    if not policy["require_full_report"]:
        return None
    names_value = policy.get("report_names", list(DEFAULT_REPORT_NAMES))
    if not isinstance(names_value, list) or not all(
        isinstance(name, str) and name for name in names_value
    ):
        raise SubmissionError("policy report_names must be string[]")
    report = choose_file(run_dir, tuple(names_value))
    builder = Path(__file__).with_name("build-full-report.py")
    run_command(
        [
            sys.executable,
            str(builder),
            "--run-dir",
            str(run_dir),
            "--output",
            str(report),
            "--validate-only",
        ]
    )
    return report


def resolve_project_profile(
    run_dir: Path,
    policy_path: Path,
    raw_profile: Any,
) -> Path | None:
    if not isinstance(raw_profile, str) or not raw_profile.strip():
        return None
    candidate = Path(raw_profile)
    if candidate.is_absolute():
        resolved = candidate.resolve()
        if resolved.is_file():
            return resolved
        raise SubmissionError(f"project_profile does not exist: {resolved}")
    candidates = [
        (policy_path.parent / candidate).resolve(),
        (run_dir / candidate).resolve(),
    ]
    for resolved in candidates:
        if resolved.is_file():
            return resolved
    raise SubmissionError(
        "project_profile does not exist relative to policy or run directory: "
        f"{raw_profile}"
    )


def validate_results(
    run_dir: Path,
    policy_path: Path,
    policy: dict[str, Any],
) -> tuple[Path, Any]:
    results_path = choose_file(run_dir, ("merged-results.json", "results.json"))
    results = load_json(results_path)
    if not policy["require_results_validation"]:
        return results_path, results

    script_dir = Path(__file__).parent
    profile_path = resolve_project_profile(
        run_dir, policy_path, policy.get("project_profile")
    )
    if results_path.name == "results.json":
        command = [str(script_dir / "validate-results.sh"), str(results_path)]
        if profile_path is not None:
            command.extend(["--profile", str(profile_path)])
    else:
        schema_version = results.get("schema_version")
        validator = (
            "validate-merged-results-v4.py"
            if schema_version == 4
            else "validate-merged-results.py"
        )
        command = [sys.executable, str(script_dir / validator), str(results_path)]
        if schema_version == 4 and profile_path is not None:
            command.extend(["--profile", str(profile_path)])
    run_command(command)
    return results_path, results


def collect_bug_evidence(value: Any, bug_id: str) -> list[str]:
    found: list[str] = []
    if isinstance(value, dict):
        bug_ids = value.get("bug_ids")
        singular = value.get("bug_id")
        matches = (
            isinstance(bug_ids, list) and bug_id in bug_ids
        ) or singular == bug_id
        if matches:
            level = value.get("evidence_strength", value.get("evidence_level"))
            if isinstance(level, str):
                found.append(level.lower())
        for child in value.values():
            found.extend(collect_bug_evidence(child, bug_id))
    elif isinstance(value, list):
        for child in value:
            found.extend(collect_bug_evidence(child, bug_id))
    return found


def is_placeholder(value: str) -> bool:
    stripped = value.strip().strip("'\"`.,;")
    return bool(
        re.fullmatch(r"<[^>\n]+>", stripped)
        or re.fullmatch(r"\$\{[^}\n]+\}", stripped)
        or re.fullmatch(
            r"(?i)(?:redacted|masked|placeholder|changeme|change_me|"
            r"xxx+|your[_-][A-Za-z0-9_-]+|\*{3,})",
            stripped,
        )
    )


def add_value_finding(
    findings: list[str],
    *,
    label: str,
    value: str,
    line_number: int,
) -> None:
    if value and not is_placeholder(value):
        findings.append(f"line {line_number}: {label}")


def add_identifier_finding(
    findings: list[str],
    *,
    label: str,
    value: str,
    line_number: int,
) -> None:
    sentinel = value.strip().strip("'\"`.,;").lower()
    if sentinel in {"0", "-1", "null", "none", "n/a", "unknown"}:
        return
    add_value_finding(
        findings,
        label=label,
        value=value,
        line_number=line_number,
    )


def scan_sensitive(
    text: str, policy: dict[str, Any]
) -> list[str]:
    findings: list[str] = []
    redaction = policy.get("redaction", {})
    if not isinstance(redaction, dict):
        raise SubmissionError("policy redaction must be an object")

    for line_number, line in enumerate(text.splitlines(), start=1):
        if re.search(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----", line):
            findings.append(f"line {line_number}: private key")
        if re.search(
            r"\b(?:github_pat_[A-Za-z0-9_]{10,}|gh[pousr]_[A-Za-z0-9]{20,})\b",
            line,
        ):
            findings.append(f"line {line_number}: GitHub token")
        bearer = re.search(r"(?i)\bBearer\s+([^\s,;]+)", line)
        if bearer:
            add_value_finding(
                findings,
                label="Bearer credential",
                value=bearer.group(1),
                line_number=line_number,
            )
        assignment = re.search(
            r"(?i)\b(password|passwd|pwd(?:_md5)?|secret|token|api[_-]?key|"
            r"authorization)\b\s*[:=]\s*([^\s,;]+)",
            line,
        )
        if assignment:
            add_value_finding(
                findings,
                label=f"secret-like field {assignment.group(1)}",
                value=assignment.group(2),
                line_number=line_number,
            )
        cli_secret = re.search(
            r"(?i)--(?:login-pwd|trade-pwd|password|token|api-key)\s+([^\s]+)",
            line,
        )
        if cli_secret:
            add_value_finding(
                findings,
                label="secret-like CLI argument",
                value=cli_secret.group(1),
                line_number=line_number,
            )
        identifier = re.search(
            r"(?i)\b(acc(?:ount)?[_ -]?id|login[_ -]?account|device[_ -]?id|"
            r"order[_ -]?id(?:[_ -]?ex)?|phone)\b\s*[:=]\s*([^\s,;]+)",
            line,
        )
        if identifier:
            add_identifier_finding(
                findings,
                label=f"sensitive identifier {identifier.group(1)}",
                value=identifier.group(2),
                line_number=line_number,
            )
        localized_identifier = re.search(
            r"(?:账号|账户(?:\s*ID)?|订单号|设备(?:\s*ID|标识)|手机号)"
            r"\s*[:=：]\s*([^\s,;，；]+)",
            line,
            re.IGNORECASE,
        )
        if localized_identifier:
            add_identifier_finding(
                findings,
                label="localized sensitive identifier",
                value=localized_identifier.group(1),
                line_number=line_number,
            )
        table_identifier = re.search(
            r"(?i)\|\s*(?:acc(?:ount)?[_ -]?id|login[_ -]?account|"
            r"device[_ -]?id|order[_ -]?id(?:[_ -]?ex)?|账号|账户(?:\s*ID)?|"
            r"订单号|设备(?:\s*ID|标识)|手机号)\s*\|\s*([^|]+)\|",
            line,
        )
        if table_identifier:
            add_identifier_finding(
                findings,
                label="sensitive identifier in table",
                value=table_identifier.group(1),
                line_number=line_number,
            )
        cli_identifier = re.search(
            r"(?i)--(?:acc-id|login-account|device-id|order-id)\s+([^\s]+)",
            line,
        )
        if cli_identifier:
            add_identifier_finding(
                findings,
                label="sensitive CLI identifier",
                value=cli_identifier.group(1),
                line_number=line_number,
            )
        if redaction.get("block_emails", True) and re.search(
            r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b", line
        ):
            findings.append(f"line {line_number}: email address")
        if re.search(r"(?:/Users|/home)/[^/\s]+/", line) or re.search(
            r"(?i)[A-Z]:\\Users\\[^\\\s]+\\", line
        ):
            findings.append(f"line {line_number}: local user path")
        if redaction.get("block_nonlocal_ips", True):
            for address in re.findall(
                r"(?<![A-Za-z0-9])(?:\d{1,3}\.){3}\d{1,3}(?![A-Za-z0-9])",
                line,
            ):
                if address not in {"127.0.0.1", "0.0.0.0", "255.255.255.255"}:
                    findings.append(
                        f"line {line_number}: non-local IPv4 address"
                    )

    extra = redaction.get("additional_patterns", [])
    if not isinstance(extra, list):
        raise SubmissionError("redaction.additional_patterns must be an array")
    for entry in extra:
        if not isinstance(entry, dict):
            raise SubmissionError(
                "redaction.additional_patterns entries must be objects"
            )
        label = entry.get("label")
        pattern = entry.get("pattern")
        if not isinstance(label, str) or not isinstance(pattern, str):
            raise SubmissionError(
                "redaction pattern requires string label and pattern"
            )
        try:
            compiled = re.compile(pattern, re.MULTILINE)
        except re.error as exc:
            raise SubmissionError(
                f"invalid redaction regex {label}: {exc}"
            ) from exc
        for match in compiled.finditer(text):
            line_number = text.count("\n", 0, match.start()) + 1
            findings.append(f"line {line_number}: {label}")
    return sorted(set(findings))


def render_title(template: str, metadata: dict[str, Any]) -> str:
    fields = {
        key: "" if value is None else str(value)
        for key, value in metadata.items()
        if isinstance(key, str)
    }
    try:
        title = template.format_map(fields).strip()
    except KeyError as exc:
        raise SubmissionError(
            f"title_template references missing field: {exc.args[0]}"
        ) from exc
    if not title:
        raise SubmissionError("rendered issue title is empty")
    if len(title) > 256:
        raise SubmissionError("rendered issue title exceeds 256 characters")
    return title


def build_candidate(
    path: Path,
    results: Any,
    policy: dict[str, Any],
) -> tuple[Candidate | None, str | None]:
    text = canonical_text(path)
    metadata = extract_bug_metadata(text, path)
    bug_id = require_string(metadata, "id", path)
    status = require_string(metadata, "status", path).upper()
    evidence_level = require_string(
        metadata, "evidence_level", path
    ).lower()
    eligible_statuses = {
        value.upper() for value in policy["eligible_statuses"]
    }
    eligible_levels = {
        value.lower() for value in policy["eligible_evidence_levels"]
    }
    if status not in eligible_statuses:
        return None, f"status={status} is not eligible"
    if evidence_level not in eligible_levels:
        return None, f"evidence_level={evidence_level} is not eligible"

    typed_levels = collect_bug_evidence(results, bug_id)
    eligible_typed = [
        level for level in typed_levels if level in eligible_levels
    ]
    if not eligible_typed:
        raise SubmissionError(
            f"{path.name} claims {evidence_level}, but validated results have "
            f"no confirmed/proven occurrence referencing {bug_id}"
        )
    strongest = max(eligible_typed, key=lambda level: EVIDENCE_RANK[level])
    if EVIDENCE_RANK[strongest] < EVIDENCE_RANK[evidence_level]:
        raise SubmissionError(
            f"{path.name} metadata evidence {evidence_level} exceeds "
            f"results evidence {strongest}"
        )

    title = require_string(metadata, "title", path)
    source_run = require_string(metadata, "found_by_run", path)
    version_found = require_string(metadata, "version_found", path)
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+:-]{2,255}", source_run):
        raise SubmissionError(
            f"{path.name} bug.found_by_run is not a safe marker value"
        )
    submission_key_value = metadata.get("submission_key")
    if policy["require_submission_key"]:
        submission_key = require_string(metadata, "submission_key", path)
    elif isinstance(submission_key_value, str) and submission_key_value.strip():
        submission_key = submission_key_value.strip()
    else:
        submission_key = f"{version_found}:{title}"
    if not re.fullmatch(r"[a-z0-9][a-z0-9._-]{2,127}", submission_key):
        raise SubmissionError(
            f"{path.name} bug.submission_key must match "
            "[a-z0-9][a-z0-9._-]{2,127}"
        )

    findings = scan_sensitive(text, policy)
    if findings:
        raise SubmissionError(
            f"{path.name} failed secret/PII scan:\n- "
            + "\n- ".join(findings)
        )

    repository = policy["repository"]
    fingerprint = sha256_text(
        f"github\0{repository.lower()}\0{submission_key}"
    )
    issue_title = render_title(policy["title_template"], metadata)
    body_preamble = policy.get("body_preamble", DEFAULT_BODY_PREAMBLE).strip()
    issue_body = (
        f"<!-- {MARKER_PREFIX}: {fingerprint} -->\n"
        f"<!-- {SOURCE_RUN_PREFIX}: {source_run} -->\n"
        f"<!-- {SUBMISSION_KEY_PREFIX}: {submission_key} -->\n\n"
        f"> {body_preamble}\n\n"
        f"{text}"
    )
    max_body_bytes = policy.get("max_body_bytes", 60000)
    if (
        not isinstance(max_body_bytes, int)
        or max_body_bytes <= 0
        or len(issue_body.encode("utf-8")) > max_body_bytes
    ):
        raise SubmissionError(
            f"{path.name} issue body exceeds max_body_bytes={max_body_bytes}"
        )
    return (
        Candidate(
            path=path,
            text=text,
            metadata=metadata,
            bug_id=bug_id,
            title=title,
            source_run=source_run,
            version_found=version_found,
            submission_key=submission_key,
            evidence_level=evidence_level,
            fingerprint=fingerprint,
            issue_title=issue_title,
            issue_body=issue_body,
        ),
        None,
    )


def github_preflight(repository: str) -> None:
    run_command(["gh", "auth", "status", "--hostname", "github.com"])
    result = run_command(
        [
            "gh",
            "repo",
            "view",
            repository,
            "--json",
            "viewerPermission,hasIssuesEnabled",
        ]
    )
    try:
        state = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise SubmissionError(f"invalid gh repo view output: {exc}") from exc
    if not state.get("hasIssuesEnabled"):
        raise SubmissionError(f"GitHub Issues are disabled for {repository}")
    if state.get("viewerPermission") not in {"ADMIN", "MAINTAIN", "WRITE"}:
        raise SubmissionError(
            f"GitHub permission is {state.get('viewerPermission')}, need WRITE"
        )


def github_issues(repository: str) -> list[dict[str, Any]]:
    result = run_command(
        [
            "gh",
            "api",
            "--method",
            "GET",
            "--paginate",
            "--slurp",
            f"repos/{repository}/issues?state=all&per_page=100",
        ]
    )
    try:
        pages = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise SubmissionError(f"invalid GitHub issues response: {exc}") from exc
    issues: list[dict[str, Any]] = []
    if isinstance(pages, list):
        for page in pages:
            if isinstance(page, list):
                issues.extend(
                    issue
                    for issue in page
                    if isinstance(issue, dict) and "pull_request" not in issue
                )
    return issues


def find_existing_issue(
    issues: list[dict[str, Any]], fingerprint: str
) -> dict[str, Any] | None:
    marker = f"<!-- {MARKER_PREFIX}: {fingerprint} -->"
    for issue in issues:
        body = issue.get("body")
        if isinstance(body, str) and marker in body:
            return issue
    return None


def github_create_issue(
    repository: str,
    candidate: Candidate,
    labels: list[str],
) -> dict[str, Any]:
    payload = {
        "title": candidate.issue_title,
        "body": candidate.issue_body,
        "labels": labels,
    }
    result = run_command(
        [
            "gh",
            "api",
            "--method",
            "POST",
            f"repos/{repository}/issues",
            "--input",
            "-",
        ],
        input_text=json.dumps(payload, ensure_ascii=False),
    )
    try:
        issue = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise SubmissionError(f"invalid GitHub create response: {exc}") from exc
    if not isinstance(issue.get("number"), int) or not isinstance(
        issue.get("html_url"), str
    ):
        raise SubmissionError("GitHub create response lacks number/html_url")
    return issue


def load_ledger(path: Path, repository: str) -> dict[str, Any]:
    if not path.exists():
        return {
            "schema_version": 1,
            "repository": repository,
            "updated_at": None,
            "submissions": {},
        }
    ledger = load_json(path)
    if (
        not isinstance(ledger, dict)
        or ledger.get("schema_version") != 1
        or ledger.get("repository") != repository
        or not isinstance(ledger.get("submissions"), dict)
    ):
        raise SubmissionError(f"invalid issue submission ledger: {path}")
    return ledger


def record_submission(
    ledger_path: Path,
    ledger: dict[str, Any],
    candidate: Candidate,
    issue: dict[str, Any],
    status: str,
) -> None:
    timestamp = now_iso()
    ledger["updated_at"] = timestamp
    ledger["submissions"][candidate.submission_key] = {
        "bug_id": candidate.bug_id,
        "source_file": str(candidate.path.name),
        "source_run": candidate.source_run,
        "submission_fingerprint": candidate.fingerprint,
        "status": status,
        "issue_number": issue["number"],
        "issue_url": issue["html_url"],
        "issue_state": issue.get("state"),
        "submitted_at": timestamp,
    }
    atomic_write_json(ledger_path, ledger)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Validate complete Better Test bug reports and create one "
            "idempotent GitHub issue per confirmed/proven bug."
        )
    )
    parser.add_argument("--run-dir", required=True, type=Path)
    parser.add_argument("--policy", required=True, type=Path)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--validate-only", action="store_true")
    action.add_argument("--dry-run", action="store_true")
    action.add_argument("--submit", action="store_true")
    parser.add_argument(
        "--offline",
        action="store_true",
        help="Skip GitHub preflight/dedupe; valid only with validate/dry-run.",
    )
    parser.add_argument(
        "--bug",
        action="append",
        default=[],
        help="Restrict to a bug id or submission key; repeatable.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.offline and args.submit:
        raise SubmissionError("--offline cannot be used with --submit")

    run_dir = args.run_dir.resolve()
    policy_path = args.policy.resolve()
    if not run_dir.is_dir():
        raise SubmissionError(f"run directory does not exist: {run_dir}")
    if not policy_path.is_file():
        raise SubmissionError(f"policy does not exist: {policy_path}")
    policy = load_policy(policy_path)
    if not policy["enabled"]:
        raise SubmissionError("issue submission policy is disabled")

    validate_full_report(run_dir, policy)
    _, results = validate_results(run_dir, policy_path, policy)
    bugs_dir = run_dir / "bugs"
    bug_paths = sorted(
        path
        for path in bugs_dir.glob("BUG-*.md")
        if path.is_file() and not path.is_symlink()
    )
    if not bug_paths:
        raise SubmissionError(f"no BUG-*.md files found under {bugs_dir}")

    selected = set(args.bug)
    candidates: list[Candidate] = []
    skipped: list[dict[str, str]] = []
    for path in bug_paths:
        candidate, reason = build_candidate(path, results, policy)
        if candidate is None:
            skipped.append({"file": path.name, "reason": reason or "ineligible"})
            continue
        if selected and not (
            candidate.bug_id in selected
            or candidate.submission_key in selected
        ):
            skipped.append({"file": path.name, "reason": "not selected"})
            continue
        candidates.append(candidate)

    if selected:
        matched = {
            value
            for candidate in candidates
            for value in (candidate.bug_id, candidate.submission_key)
        }
        missing = sorted(selected - matched)
        if missing:
            raise SubmissionError(
                f"selected bugs are not eligible/found: {', '.join(missing)}"
            )

    keys = [candidate.submission_key for candidate in candidates]
    duplicate_keys = sorted(
        {key for key in keys if keys.count(key) > 1}
    )
    if duplicate_keys:
        raise SubmissionError(
            "eligible Bug Reports reuse submission_key: "
            + ", ".join(duplicate_keys)
        )

    repository = policy["repository"]
    ledger_name = policy.get("ledger_name", DEFAULT_LEDGER_NAME)
    if not isinstance(ledger_name, str) or "/" in ledger_name:
        raise SubmissionError("policy ledger_name must be a plain filename")
    ledger_path = run_dir / ledger_name
    submitted: list[dict[str, Any]] = []
    planned: list[dict[str, Any]] = []

    lock = submission_lock(repository) if args.submit else nullcontext()
    with lock:
        issues: list[dict[str, Any]] = []
        if not args.offline and (args.dry_run or args.submit):
            github_preflight(repository)
            issues = github_issues(repository)
        ledger = load_ledger(ledger_path, repository) if args.submit else None

        for candidate in candidates:
            existing = (
                find_existing_issue(issues, candidate.fingerprint)
                if issues
                else None
            )
            if existing is not None:
                if args.submit:
                    if ledger is None:
                        raise SubmissionError(
                            "submission ledger was not initialized"
                        )
                    record_submission(
                        ledger_path,
                        ledger,
                        candidate,
                        existing,
                        "linked_existing",
                    )
                submitted.append(
                    {
                        "bug_id": candidate.bug_id,
                        "submission_key": candidate.submission_key,
                        "status": "linked_existing",
                        "issue_number": existing.get("number"),
                        "issue_url": existing.get("html_url"),
                    }
                )
                continue

            planned.append(
                {
                    "bug_id": candidate.bug_id,
                    "submission_key": candidate.submission_key,
                    "evidence_level": candidate.evidence_level,
                    "title": candidate.issue_title,
                    "submission_fingerprint": candidate.fingerprint,
                }
            )
            if not args.submit:
                continue
            if ledger is None:
                raise SubmissionError("submission ledger was not initialized")
            issue = github_create_issue(
                repository, candidate, list(policy["labels"])
            )
            issues.append(issue)
            record_submission(
                ledger_path, ledger, candidate, issue, "created"
            )
            submitted.append(
                {
                    "bug_id": candidate.bug_id,
                    "submission_key": candidate.submission_key,
                    "status": "created",
                    "issue_number": issue["number"],
                    "issue_url": issue["html_url"],
                }
            )

    output = {
        "repository": repository,
        "mode": (
            "submit"
            if args.submit
            else "dry-run"
            if args.dry_run
            else "validate-only"
        ),
        "eligible_count": len(candidates),
        "planned": planned,
        "submitted": submitted,
        "skipped": skipped,
        "ledger": str(ledger_path) if args.submit and submitted else None,
    }
    print(json.dumps(output, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, SubmissionError) as exc:
        print(f"[bug-issue-submission] FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
