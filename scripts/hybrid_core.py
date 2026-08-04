#!/usr/bin/env python3
"""Shared contracts and semantic checks for Better Test hybrid testing.

The module intentionally uses only the Python standard library. JSON Schema
files document the public contract; these checks enforce cross-field and
filesystem invariants that JSON Schema alone cannot express.
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import re
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any, Callable


CONTRACT_VERSION = "1.0.0"
TERMINAL_STATUSES = {
    "pass",
    "pass_with_caveat",
    "pass_known_legacy_behavior",
    "fail",
    "partial_fail",
    "blocked",
    "skip",
    "excluded",
    "pending",
    "partial",
}
PASS_STATUSES = {"pass"}
SOURCE_ONLY_KINDS = {"static", "compile", "unit", "source_review", "mutation"}
TEST_KINDS = SOURCE_ONLY_KINDS | {
    "integration",
    "artifact_identity",
    "install",
    "process",
    "session",
    "runtime",
    "business_canary",
    "write_lifecycle",
    "recovery",
    "negative",
    "compare",
    "chaos",
    "legacy",
}
RUNTIME_CLAIMS = {
    "observed_behavior",
    "runtime_readiness",
    "business_canary",
    "write_lifecycle",
    "release_gate",
}
RUNTIME_EVIDENCE_KINDS = {
    "runtime",
    "live",
    "process",
    "session",
    "external",
    "business_canary",
    "write_lifecycle",
}
CAPABILITY_IDS = {
    "source-map",
    "source-impact",
    "runtime-probe",
    "artifact-identity",
    "process-identity",
    "session-readiness",
    "typed-subject-identity",
}
CLAIM_RANK = {
    "observation": 0,
    "behavior": 1,
    "source_correctness": 2,
    "build_correctness": 3,
    "artifact_identity": 4,
    "observed_behavior": 5,
    "runtime_readiness": 6,
    "business_canary": 7,
    "write_lifecycle": 8,
    "release_gate": 9,
}
OBJECTIVE_MAX_CLAIM = {
    "source_change": "source_correctness",
    "package_validation": "runtime_readiness",
    "behavior_regression": "runtime_readiness",
    "release_decision": "release_gate",
    "bug_investigation": "observed_behavior",
    "legacy_compatibility": "behavior",
}
OBJECTIVE_REQUIRED_CAPABILITIES = {
    "source_change": {"source-map", "source-impact"},
    "package_validation": {
        "artifact-identity",
        "process-identity",
        "runtime-probe",
        "typed-subject-identity",
    },
    "behavior_regression": {
        "artifact-identity",
        "process-identity",
        "runtime-probe",
        "typed-subject-identity",
    },
    "release_decision": {
        "artifact-identity",
        "process-identity",
        "runtime-probe",
        "session-readiness",
        "typed-subject-identity",
    },
    "bug_investigation": {
        "source-map",
        "source-impact",
        "runtime-probe",
        "typed-subject-identity",
    },
    "legacy_compatibility": set(),
}


def derive_mode(available: set[str], hybrid_enabled: bool = True) -> str:
    if not hybrid_enabled:
        return "blackbox"
    source_capable = {"source-map", "source-impact"}.issubset(available)
    runtime_capable = "runtime-probe" in available
    if source_capable and runtime_capable:
        return "hybrid"
    if source_capable:
        return "whitebox"
    return "blackbox"


def derive_claim_ceiling(objective: str, available: set[str]) -> str:
    objective_ceiling = OBJECTIVE_MAX_CLAIM[objective]
    missing = OBJECTIVE_REQUIRED_CAPABILITIES[objective] - available
    if not missing:
        return objective_ceiling
    supported = ["behavior"]
    if {"source-map", "source-impact"}.issubset(available):
        supported.append("source_correctness")
    if "artifact-identity" in available:
        supported.append("artifact_identity")
    if {"runtime-probe", "typed-subject-identity"}.issubset(available):
        supported.append("observed_behavior")
    if {
        "artifact-identity",
        "process-identity",
        "runtime-probe",
        "typed-subject-identity",
    }.issubset(available):
        supported.append("runtime_readiness")
    capability_ceiling = max(supported, key=lambda claim: CLAIM_RANK[claim])
    return min(
        (objective_ceiling, capability_ceiling),
        key=lambda claim: CLAIM_RANK[claim],
    )
SUBJECT_TYPES = {
    "source",
    "build",
    "artifact",
    "installation",
    "process",
    "session",
    "external_service",
    "unknown",
}
COVERAGE_LANES = {
    "surface",
    "inventory",
    "code",
    "diff",
    "risk",
    "invariant",
    "selection",
}
SECRET_KEY = re.compile(r"(^|[_-])(api[_-]?key|token|password|passwd|secret|pwd_md5|otp|cipher)($|[_-])", re.IGNORECASE)
SECRET_VALUE = re.compile(r"(github_pat_|ghp_[A-Za-z0-9]|Bearer\s+[A-Za-z0-9._-]{12,})")


def _schema_type_matches(value: Any, expected: str) -> bool:
    return {
        "object": isinstance(value, dict),
        "array": isinstance(value, list),
        "string": isinstance(value, str),
        "integer": isinstance(value, int) and not isinstance(value, bool),
        "number": isinstance(value, (int, float)) and not isinstance(value, bool),
        "boolean": isinstance(value, bool),
        "null": value is None,
    }.get(expected, True)


def _resolve_local_ref(root: dict[str, Any], reference: str) -> dict[str, Any]:
    if not reference.startswith("#/"):
        raise ValueError(f"unsupported schema reference: {reference}")
    value: Any = root
    for raw in reference[2:].split("/"):
        key = raw.replace("~1", "/").replace("~0", "~")
        value = value[key]
    if not isinstance(value, dict):
        raise ValueError(f"schema reference is not an object: {reference}")
    return value


def validate_json_schema(
    value: Any,
    schema: dict[str, Any],
    root: dict[str, Any] | None = None,
    path: str = "$",
) -> list[str]:
    """Validate the JSON Schema subset used by Better Test public contracts.

    This keeps the skill self-contained while executing, rather than merely
    publishing, its Draft 2020-12 contracts. Unsupported remote refs fail
    closed.
    """

    root = root or schema
    if "$ref" in schema:
        try:
            return validate_json_schema(value, _resolve_local_ref(root, schema["$ref"]), root, path)
        except (KeyError, TypeError, ValueError) as exc:
            return [f"schema {path}: {exc}"]
    errors: list[str] = []
    for keyword in ("allOf",):
        for branch in schema.get(keyword, []):
            errors.extend(validate_json_schema(value, branch, root, path))
    if "anyOf" in schema:
        matches = [validate_json_schema(value, branch, root, path) for branch in schema["anyOf"]]
        if not any(not result for result in matches):
            errors.append(f"schema {path}: does not match anyOf")
    if "oneOf" in schema:
        matches = [validate_json_schema(value, branch, root, path) for branch in schema["oneOf"]]
        if sum(not result for result in matches) != 1:
            errors.append(f"schema {path}: does not match exactly one oneOf branch")
    conditional = schema.get("if")
    if isinstance(conditional, dict) and not validate_json_schema(value, conditional, root, path):
        then = schema.get("then")
        if isinstance(then, dict):
            errors.extend(validate_json_schema(value, then, root, path))
    if "const" in schema and value != schema["const"]:
        errors.append(f"schema {path}: must equal {schema['const']!r}")
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"schema {path}: value is not in enum")
    expected_type = schema.get("type")
    if expected_type is not None:
        candidates = expected_type if isinstance(expected_type, list) else [expected_type]
        if not any(_schema_type_matches(value, candidate) for candidate in candidates):
            return errors + [f"schema {path}: expected type {expected_type!r}"]
    if isinstance(value, str):
        if len(value) < schema.get("minLength", 0):
            errors.append(f"schema {path}: string is shorter than minLength")
        pattern = schema.get("pattern")
        if isinstance(pattern, str) and re.search(pattern, value) is None:
            errors.append(f"schema {path}: string does not match pattern")
        if schema.get("format") == "date-time" and not is_timestamp(value):
            errors.append(f"schema {path}: invalid date-time")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            errors.append(f"schema {path}: below minimum")
        if "maximum" in schema and value > schema["maximum"]:
            errors.append(f"schema {path}: above maximum")
    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0):
            errors.append(f"schema {path}: array is shorter than minItems")
        if schema.get("uniqueItems"):
            encoded = [json.dumps(item, sort_keys=True, separators=(",", ":")) for item in value]
            if len(encoded) != len(set(encoded)):
                errors.append(f"schema {path}: array items are not unique")
        item_schema = schema.get("items")
        if isinstance(item_schema, dict):
            for index, item in enumerate(value):
                errors.extend(validate_json_schema(item, item_schema, root, f"{path}[{index}]"))
    if isinstance(value, dict):
        required = schema.get("required", [])
        for key in required:
            if key not in value:
                errors.append(f"schema {path}: missing required property {key}")
        properties = schema.get("properties", {})
        for key, child in value.items():
            if key in properties:
                errors.extend(validate_json_schema(child, properties[key], root, f"{path}.{key}"))
            elif schema.get("additionalProperties") is False:
                errors.append(f"schema {path}: additional property {key} is not allowed")
            elif isinstance(schema.get("additionalProperties"), dict):
                errors.extend(
                    validate_json_schema(child, schema["additionalProperties"], root, f"{path}.{key}")
                )
        property_names = schema.get("propertyNames")
        if isinstance(property_names, dict):
            for key in value:
                errors.extend(validate_json_schema(key, property_names, root, f"{path}.<propertyName>"))
    return errors


def validate_schema_file(kind: str, document: Any) -> list[str]:
    schema_path = Path(__file__).resolve().parent.parent / "schemas" / f"{kind}.schema.json"
    try:
        schema = load_json(schema_path)
    except (OSError, ValueError) as exc:
        return [f"schema load failed for {kind}: {exc}"]
    if not isinstance(schema, dict):
        return [f"schema root for {kind} must be an object"]
    return validate_json_schema(document, schema)


def _reject_constant(value: str) -> None:
    raise ValueError(f"non-standard JSON constant: {value}")


def _reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def loads_json(payload: str) -> Any:
    """Parse strict JSON, rejecting duplicate keys and non-finite constants."""
    return json.loads(
        payload,
        parse_constant=_reject_constant,
        object_pairs_hook=_reject_duplicate_keys,
    )


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return loads_json(handle.read())


def dump_json(document: Any) -> str:
    return json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def sha256_json(document: Any) -> str:
    payload = json.dumps(
        document, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def is_timestamp(value: Any) -> bool:
    if not isinstance(value, str) or not value.strip() or value != value.strip():
        return False
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return False
    return parsed.tzinfo is not None and parsed.utcoffset() is not None


def _nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip()) and value == value.strip()


def normalize_status(value: Any) -> Any:
    if not isinstance(value, str):
        return value
    normalized = value.strip().lower().replace("-", "_")
    return normalized


def _is_sha256(value: Any) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(char in "0123456789abcdef" for char in value)
    )


def _unique_ids(rows: Any, field: str, label: str, errors: list[str]) -> set[str]:
    if not isinstance(rows, list):
        errors.append(f"{label} must be an array")
        return set()
    seen: set[str] = set()
    for index, row in enumerate(rows):
        if not isinstance(row, dict) or not _nonempty(row.get(field)):
            errors.append(f"{label}[{index}].{field} must be a non-empty string")
            continue
        value = row[field]
        if value in seen:
            errors.append(f"duplicate {label} {field}: {value}")
        seen.add(value)
    return seen


def _find_secrets(value: Any, location: str = "$", *, key: str | None = None) -> list[str]:
    findings: list[str] = []
    if key is not None and SECRET_KEY.search(key):
        findings.append(location)
    if isinstance(value, str) and SECRET_VALUE.search(value):
        findings.append(location)
    elif isinstance(value, dict):
        for child_key, child in value.items():
            findings.extend(_find_secrets(child, f"{location}.{child_key}", key=child_key))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            findings.extend(_find_secrets(child, f"{location}[{index}]"))
    return findings


def validate_project_profile(document: Any, _path: Path | None = None) -> list[str]:
    errors: list[str] = []
    if not isinstance(document, dict):
        return ["project profile must be an object"]
    for finding in sorted(set(_find_secrets(document))):
        errors.append(f"project profile contains a secret-like field or value at {finding}")
    if document.get("schema_version") != 1:
        errors.append("project profile schema_version must be integer 1")
    if document.get("contract_version") != CONTRACT_VERSION:
        errors.append(f"contract_version must be {CONTRACT_VERSION}")
    if not _nonempty(document.get("project_id")):
        errors.append("project_id must be a non-empty string")
    versions = document.get("result_versions")
    if not isinstance(versions, list) or not versions or not all(
        type(value) is int and value in {3, 4} for value in versions
    ):
        errors.append("result_versions must be a non-empty array containing only 3 or 4")
    providers = document.get("providers")
    provider_ids = _unique_ids(providers, "id", "providers", errors)
    if isinstance(providers, list):
        for index, provider in enumerate(providers):
            if not isinstance(provider, dict):
                continue
            command = provider.get("command")
            if not isinstance(command, list) or not command or not all(
                _nonempty(value) for value in command
            ):
                errors.append(f"providers[{index}].command must be a non-empty string array")
            else:
                for part in command:
                    if part.startswith("/Users/") or part.startswith("/home/"):
                        errors.append(
                            f"providers[{index}].command contains a personal absolute path"
                        )
            capabilities = provider.get("capabilities")
            if not isinstance(capabilities, list) or not all(
                _nonempty(value) for value in capabilities
            ):
                errors.append(f"providers[{index}].capabilities must be a string array")
            trust = provider.get("trust")
            if not isinstance(trust, dict):
                errors.append(f"providers[{index}].trust must be an object")
                continue
            if trust.get("source_access") != "read-only":
                errors.append(f"providers[{index}] must default source_access to read-only")
            if trust.get("network") not in {"deny", "explicit"}:
                errors.append(f"providers[{index}].trust.network must be deny or explicit")
            if trust.get("external_writes") not in {"deny", "explicit"}:
                errors.append(
                    f"providers[{index}].trust.external_writes must be deny or explicit"
                )
            path_scope = trust.get("path_scope")
            if not isinstance(path_scope, list) or not path_scope or not all(
                _nonempty(value) and not Path(value).is_absolute() for value in path_scope
            ):
                errors.append(
                    f"providers[{index}].trust.path_scope must be a non-empty relative-path array"
                )
            if not (_nonempty(trust.get("version")) or _is_sha256(trust.get("sha256"))):
                errors.append(f"providers[{index}] trust requires version or sha256")
            dependencies = trust.get("dependencies", [])
            if not isinstance(dependencies, list):
                errors.append(f"providers[{index}].trust.dependencies must be an array")
            else:
                for dependency_index, dependency in enumerate(dependencies):
                    if not isinstance(dependency, dict) or not _nonempty(dependency.get("path")):
                        errors.append(f"providers[{index}].trust.dependencies[{dependency_index}] requires path")
                    elif dependency["path"].startswith(("/Users/", "/home/")):
                        errors.append(f"providers[{index}].trust.dependencies[{dependency_index}] contains personal absolute path")
                    if not isinstance(dependency, dict) or not _is_sha256(dependency.get("sha256")):
                        errors.append(f"providers[{index}].trust.dependencies[{dependency_index}] requires sha256")
    if len(provider_ids) == 0:
        errors.append("at least one provider is required")
    policy = document.get("evidence_policy")
    if not isinstance(policy, dict):
        errors.append("evidence_policy must be an object")
    else:
        if policy.get("unknown_impact") != "expand-safe-default":
            errors.append("evidence_policy.unknown_impact must be expand-safe-default")
        lanes = policy.get("safe_default_lanes")
        if not isinstance(lanes, list) or not lanes or not all(_nonempty(x) for x in lanes):
            errors.append("evidence_policy.safe_default_lanes must be a non-empty string array")
        elif any(lane not in COVERAGE_LANES for lane in lanes):
            errors.append("evidence_policy.safe_default_lanes contains an unsupported lane")
    return errors


def validate_capabilities(document: Any, _path: Path | None = None) -> list[str]:
    errors: list[str] = []
    if not isinstance(document, dict):
        return ["capability document must be an object"]
    provider = document.get("provider")
    if not isinstance(provider, dict) or not all(
        _nonempty(provider.get(key)) for key in ("id", "version")
    ):
        errors.append("provider.id is required")
    elif not _is_sha256(provider.get("implementation_sha256")):
        errors.append("provider.implementation_sha256 is required")
    capabilities = document.get("capabilities")
    names = _unique_ids(capabilities, "name", "capabilities", errors)
    if isinstance(capabilities, list):
        for row in capabilities:
            if not isinstance(row, dict):
                continue
            if row.get("status") not in {"available", "unavailable", "unconfigured", "error"}:
                errors.append(f"capability {row.get('name')} has unsupported status")
            if not _nonempty(row.get("evidence")):
                errors.append(f"capability {row.get('name')} requires evidence")
    if not names:
        errors.append("capabilities must not be empty")
    omitted_standard = CAPABILITY_IDS - names
    if omitted_standard:
        errors.append(
            "capability document omits standard rows: "
            + ", ".join(sorted(omitted_standard))
        )
    return errors


def validate_capabilities_against_profile(
    capabilities_document: Any, profile_document: Any
) -> list[str]:
    """Bind a capability probe to the exact allowlisted provider implementation."""
    if not isinstance(capabilities_document, dict) or not isinstance(profile_document, dict):
        return ["capabilities and project profile must be objects"]
    provider = capabilities_document.get("provider", {})
    declared = next(
        (
            row
            for row in profile_document.get("providers", [])
            if isinstance(row, dict) and row.get("id") == provider.get("id")
        ),
        None,
    )
    if not isinstance(declared, dict):
        return ["capabilities provider is not declared by project profile"]
    errors: list[str] = []
    trust = declared.get("trust", {})
    if provider.get("version") != trust.get("version"):
        errors.append("capabilities provider version differs from profile trust")
    if provider.get("implementation_sha256") != trust.get("sha256"):
        errors.append("capabilities provider implementation differs from profile trust")
    available = {
        row.get("name")
        for row in capabilities_document.get("capabilities", [])
        if isinstance(row, dict)
        and row.get("status") == "available"
        and row.get("name") in CAPABILITY_IDS
    }
    if not available.issubset(set(declared.get("capabilities", []))):
        errors.append("available capabilities exceed profile provider declaration")
    return errors


def validate_source_map(document: Any, _path: Path | None = None) -> list[str]:
    errors: list[str] = []
    if not isinstance(document, dict):
        return ["source map must be an object"]
    if document.get("schema_version") != 1:
        errors.append("source map schema_version must be integer 1")
    if document.get("contract_version") != CONTRACT_VERSION:
        errors.append(f"contract_version must be {CONTRACT_VERSION}")
    if not is_timestamp(document.get("generated_at")):
        errors.append("generated_at must be an ISO 8601 timestamp with timezone")
    provider = document.get("provider")
    if not isinstance(provider, dict) or not all(
        _nonempty(provider.get(key)) for key in ("id", "version")
    ):
        errors.append("provider.id and provider.version are required")
    source = document.get("source")
    if not isinstance(source, dict):
        errors.append("source must be an object")
    else:
        if source.get("type") != "source" or not _nonempty(source.get("subject_id")):
            errors.append("source requires type=source and subject_id")
        identity = source.get("identity")
        if not isinstance(identity, dict):
            errors.append("source.identity must be an object")
        else:
            if not _nonempty(identity.get("commit")):
                errors.append("source.identity.commit is required")
            if type(identity.get("dirty")) is not bool:
                errors.append("source.identity.dirty must be boolean")
            if identity.get("dirty") is True and not _is_sha256(
                identity.get("worktree_fingerprint")
            ):
                errors.append("dirty source requires a 64-character worktree_fingerprint")
    units = document.get("units")
    unit_ids = _unique_ids(units, "id", "units", errors)
    risk_ids = _unique_ids(document.get("risk_units"), "id", "risk_units", errors)
    check_ids = _unique_ids(document.get("checks"), "id", "checks", errors)
    assets = document.get("native_assets")
    if not isinstance(assets, list):
        errors.append("native_assets must be an array")
    else:
        for index, asset in enumerate(assets):
            if not isinstance(asset, dict) or not _nonempty(asset.get("path")):
                errors.append(f"native_assets[{index}] requires path")
            elif Path(asset["path"]).is_absolute():
                errors.append(f"native_assets[{index}].path must be relative")
            if not isinstance(asset, dict) or not _is_sha256(asset.get("sha256")):
                errors.append(f"native_assets[{index}] requires lowercase sha256")
    known = unit_ids | risk_ids | check_ids
    edges = document.get("edges")
    if not isinstance(edges, list):
        errors.append("edges must be an array")
    else:
        for index, edge in enumerate(edges):
            if not isinstance(edge, dict):
                errors.append(f"edges[{index}] must be an object")
                continue
            for field in ("from", "to", "kind"):
                if not _nonempty(edge.get(field)):
                    errors.append(f"edges[{index}].{field} is required")
            for field in ("from", "to"):
                value = edge.get(field)
                if _nonempty(value) and value not in known:
                    errors.append(f"edges[{index}].{field} references unknown id {value}")
    return errors


def validate_source_impact(document: Any, _path: Path | None = None) -> list[str]:
    errors: list[str] = []
    if not isinstance(document, dict):
        return ["source impact must be an object"]
    if document.get("schema_version") != 1:
        errors.append("source impact schema_version must be integer 1")
    if document.get("contract_version") != CONTRACT_VERSION:
        errors.append(f"contract_version must be {CONTRACT_VERSION}")
    if not _is_sha256(document.get("source_map_sha256")):
        errors.append("source_map_sha256 must be a lowercase SHA-256")
    for field in ("base", "head"):
        if not _nonempty(document.get(field)):
            errors.append(f"{field} is required")
    changed = document.get("changed_units")
    _unique_ids(changed, "id", "changed_units", errors)
    selections = document.get("selections")
    total_selected = 0
    if not isinstance(selections, dict):
        errors.append("selections must be an object")
    else:
        selection_owners: dict[str, str] = {}
        for lane in ("required", "recommended", "excluded"):
            rows = selections.get(lane)
            _unique_ids(rows, "id", f"selections.{lane}", errors)
            if isinstance(rows, list):
                total_selected += len(rows)
                for index, row in enumerate(rows):
                    if isinstance(row, dict) and not _nonempty(row.get("reason")):
                        errors.append(f"selections.{lane}[{index}].reason is required")
                    if isinstance(row, dict) and _nonempty(row.get("id")):
                        prior_lane = selection_owners.get(row["id"])
                        if prior_lane is not None:
                            errors.append(
                                f"selection id {row['id']} appears in both {prior_lane} and {lane}"
                            )
                        selection_owners[row["id"]] = lane
    confidence = document.get("confidence")
    if not isinstance(confidence, dict):
        errors.append("confidence must be an object")
    else:
        score = confidence.get("score")
        if not isinstance(score, (int, float)) or isinstance(score, bool) or not math.isfinite(score) or not 0 <= score <= 1:
            errors.append("confidence.score must be finite and between 0 and 1")
        if confidence.get("level") not in {"high", "medium", "low"}:
            errors.append("confidence.level must be high, medium, or low")
    unknown = document.get("unknown_changes")
    if not isinstance(unknown, list):
        errors.append("unknown_changes must be an array")
    elif unknown:
        policy = document.get("fallback_policy")
        if policy != "expand-safe-default":
            errors.append("unknown changes require fallback_policy=expand-safe-default")
        required = selections.get("required", []) if isinstance(selections, dict) else []
        if not required:
            errors.append("unknown changes must not produce an empty required selection")
    if total_selected == 0:
        errors.append("source impact must contain at least one required/recommended/excluded selection")
    return errors


def _artifact_path(run_dir: Path, ref: str) -> Path | None:
    path_text = ref.split("#", 1)[0].strip()
    if path_text.startswith(("http://", "https://")):
        return None
    candidate = Path(path_text)
    if candidate.is_absolute():
        return None
    try:
        resolved = (run_dir / candidate).resolve(strict=True)
        resolved.relative_to(run_dir.resolve())
    except (OSError, ValueError):
        return None
    return resolved if resolved.is_file() else None


def validate_results_v4(
    document: Any,
    path: Path | None = None,
    trusted_profile_path: Path | None = None,
) -> list[str]:
    errors: list[str] = []
    if not isinstance(document, dict):
        return ["results v4 must be an object"]
    errors.extend(validate_schema_file("results-v4", document))
    if document.get("schema_version") != 4:
        errors.append("results schema_version must be integer 4")
    if document.get("contract_version") != CONTRACT_VERSION:
        errors.append(f"contract_version must be {CONTRACT_VERSION}")
    for field in ("version", "tester_id", "run_id", "mode", "objective"):
        if not _nonempty(document.get(field)):
            errors.append(f"top-level {field} must be a non-empty string")
    if document.get("mode") not in {"blackbox", "whitebox", "hybrid"}:
        errors.append("mode must be blackbox, whitebox, or hybrid")
    if document.get("objective") not in {
        "source_change",
        "package_validation",
        "behavior_regression",
        "release_decision",
        "bug_investigation",
        "legacy_compatibility",
    }:
        errors.append("objective is unsupported")
    for field in ("started_at", "finished_at"):
        if not is_timestamp(document.get(field)):
            errors.append(f"{field} must be an ISO 8601 timestamp with timezone")
    if is_timestamp(document.get("started_at")) and is_timestamp(document.get("finished_at")):
        start = datetime.fromisoformat(document["started_at"].replace("Z", "+00:00"))
        finish = datetime.fromisoformat(document["finished_at"].replace("Z", "+00:00"))
        if finish < start:
            errors.append("finished_at must not be earlier than started_at")

    subjects = document.get("subjects")
    subject_ids = _unique_ids(subjects, "id", "subjects", errors)
    if not subject_ids:
        errors.append("subjects must not be empty")
    subject_types: dict[str, str] = {}
    subject_identities: dict[str, dict[str, Any]] = {}
    if isinstance(subjects, list):
        for index, subject in enumerate(subjects):
            if not isinstance(subject, dict):
                continue
            subject_type = subject.get("type")
            if subject_type not in SUBJECT_TYPES:
                errors.append(f"subjects[{index}].type is unsupported: {subject_type}")
            else:
                subject_types[subject.get("id", "")] = subject_type
            identity = subject.get("identity")
            if not isinstance(identity, dict):
                errors.append(f"subjects[{index}].identity must be an object")
                continue
            subject_identities[subject.get("id", "")] = identity
            if subject_type == "source" and identity.get("dirty") is True and not _is_sha256(
                identity.get("worktree_fingerprint")
            ):
                errors.append(f"dirty source subject {subject.get('id')} requires worktree_fingerprint")
            if subject_type == "source":
                if not _nonempty(identity.get("commit")):
                    errors.append(f"source subject {subject.get('id')} requires commit")
                if type(identity.get("dirty")) is not bool:
                    errors.append(f"source subject {subject.get('id')} requires boolean dirty")
            if subject_type == "build":
                required = ("source_ref", "toolchain", "lock_sha256", "profile", "output_sha256")
                for field in required:
                    value = identity.get(field)
                    if field.endswith("sha256"):
                        if not _is_sha256(value):
                            errors.append(f"build subject {subject.get('id')} requires {field}")
                    elif not _nonempty(value):
                        errors.append(f"build subject {subject.get('id')} requires {field}")
                if not isinstance(identity.get("features"), list):
                    errors.append(f"build subject {subject.get('id')} requires features array")
            if subject_type == "artifact" and not _is_sha256(identity.get("sha256")):
                errors.append(f"artifact subject {subject.get('id')} requires sha256")
            if subject_type == "installation":
                if not _nonempty(identity.get("install_id")):
                    errors.append(f"installation subject {subject.get('id')} requires install_id")
                if not _is_sha256(identity.get("installed_executable_sha256")):
                    errors.append(
                        f"installation subject {subject.get('id')} requires installed_executable_sha256"
                    )
            if subject_type == "process":
                if type(identity.get("pid")) is not int or identity.get("pid", 0) <= 0:
                    errors.append(f"process subject {subject.get('id')} requires positive integer pid")
                if not _is_sha256(identity.get("executable_sha256")):
                    errors.append(f"process subject {subject.get('id')} requires executable_sha256")
                if not is_timestamp(identity.get("started_at")):
                    errors.append(f"process subject {subject.get('id')} requires timestamp started_at")
                elif is_timestamp(document.get("finished_at")):
                    process_started = datetime.fromisoformat(
                        identity["started_at"].replace("Z", "+00:00")
                    )
                    run_finished = datetime.fromisoformat(
                        document["finished_at"].replace("Z", "+00:00")
                    )
                    if process_started > run_finished:
                        errors.append(
                            f"process subject {subject.get('id')} started after run finished"
                        )
            if subject_type == "session":
                if not _nonempty(identity.get("session_id")):
                    errors.append(f"session subject {subject.get('id')} requires session_id")
                if identity.get("readiness") not in {"ready", "not_ready", "unknown"}:
                    errors.append(f"session subject {subject.get('id')} requires readiness")

    relations = document.get("relations")
    relation_rows: list[dict[str, Any]] = []
    if not isinstance(relations, list):
        errors.append("relations must be an array")
    else:
        for index, relation in enumerate(relations):
            if not isinstance(relation, dict):
                errors.append(f"relations[{index}] must be an object")
                continue
            relation_rows.append(relation)
            for field in ("from", "to"):
                if relation.get(field) not in subject_ids:
                    errors.append(f"relations[{index}].{field} references unknown subject")
            if relation.get("type") in {
                "built_from",
                "produced_by",
                "installed_from",
                "launched_from",
                "connected_to",
            }:
                refs = relation.get("evidence_refs")
                if not isinstance(refs, list) or not refs or not all(_nonempty(x) for x in refs):
                    errors.append(f"relations[{index}] identity relation requires evidence_refs")

    items = document.get("items")
    item_ids = _unique_ids(items, "id", "items", errors)
    evidence_ids: set[str] = set()
    evidence_subject_refs: dict[str, set[str]] = {}
    evidence_sha256: dict[str, str | None] = {}
    actual = {key: 0 for key in ("total", "passed", "failed", "blocked", "skipped", "excluded", "pending", "partial")}
    pass_breakdown = {
        "passed_unconditional": 0,
        "passed_with_caveat": 0,
        "passed_known_legacy_behavior": 0,
    }
    run_dir = path.parent if path is not None else None
    if isinstance(items, list):
        actual["total"] = len(items)
        if not items:
            errors.append("items must not be empty")
        for index, item in enumerate(items):
            if not isinstance(item, dict):
                continue
            item_id = item.get("id", f"index-{index}")
            status = normalize_status(item.get("status"))
            if status not in TERMINAL_STATUSES:
                errors.append(f"item {item_id} has unsupported status {status}")
            else:
                bucket = {
                    "pass": "passed",
                    "pass_with_caveat": "passed",
                    "pass_known_legacy_behavior": "passed",
                    "fail": "failed",
                    "partial_fail": "failed",
                    "blocked": "blocked",
                    "skip": "skipped",
                    "excluded": "excluded",
                    "pending": "pending",
                    "partial": "partial",
                }[status]
                actual[bucket] += 1
                if status == "pass":
                    pass_breakdown["passed_unconditional"] += 1
                elif status == "pass_with_caveat":
                    pass_breakdown["passed_with_caveat"] += 1
                elif status == "pass_known_legacy_behavior":
                    pass_breakdown["passed_known_legacy_behavior"] += 1
            test_kind = item.get("test_kind")
            if not _nonempty(test_kind):
                errors.append(f"item {item_id} requires test_kind")
            elif test_kind not in TEST_KINDS:
                errors.append(f"item {item_id} has unsupported test_kind")
            refs = item.get("subject_refs")
            if not isinstance(refs, list) or not refs:
                errors.append(f"item {item_id} requires non-empty subject_refs")
                refs = []
            for ref in refs:
                if ref not in subject_ids:
                    errors.append(f"item {item_id} references unknown subject {ref}")
            claim = item.get("claim_scope")
            if claim not in CLAIM_RANK:
                errors.append(f"item {item_id} has unsupported claim_scope")
            strength = item.get("evidence_strength")
            if strength not in {"indirect", "direct", "binary", "confirmed", "proven"}:
                errors.append(f"item {item_id} has unsupported evidence_strength")
            if status in {"pass", "pass_with_caveat", "pass_known_legacy_behavior"} and strength == "indirect":
                errors.append(f"pass item {item_id} requires direct-or-stronger evidence")
            if status in {"skip", "excluded", "blocked", "pass_with_caveat", "pass_known_legacy_behavior"} and not _nonempty(item.get("reason")):
                errors.append(f"item {item_id} with status {status} requires reason")
            assertion = item.get("assertion")
            if status in {"pass", "pass_with_caveat", "pass_known_legacy_behavior"} and (
                not isinstance(assertion, dict)
                or not _nonempty(assertion.get("field"))
                or assertion.get("value") is None
            ):
                errors.append(f"pass item {item_id} requires assertion.field and assertion.value")
            item_subject_types = {subject_types.get(ref) for ref in refs}
            if claim in RUNTIME_CLAIMS and not item_subject_types.intersection(
                {"process", "session", "external_service"}
            ):
                errors.append(f"runtime/release claim {item_id} lacks a runtime subject")
            if test_kind in SOURCE_ONLY_KINDS and claim in RUNTIME_CLAIMS:
                errors.append(f"source-only test {item_id} cannot support {claim}")
            sources = item.get("evidence_sources")
            if not isinstance(sources, list) or not sources:
                errors.append(f"item {item_id} requires evidence_sources")
                continue
            for source_index, source in enumerate(sources):
                if not isinstance(source, dict) or not _nonempty(source.get("id")):
                    errors.append(f"item {item_id} evidence_sources[{source_index}] requires id")
                    continue
                source_id = source["id"]
                if source_id in evidence_ids:
                    errors.append(f"duplicate evidence id: {source_id}")
                evidence_ids.add(source_id)
                evidence_subject_refs[source_id] = set(refs)
                evidence_sha256[source_id] = source.get("sha256")
                ref = source.get("artifact_ref")
                if not _nonempty(ref):
                    errors.append(f"evidence {source_id} requires artifact_ref")
                elif run_dir is not None and _artifact_path(run_dir, ref) is None:
                    errors.append(f"evidence {source_id} artifact is missing or outside run dir: {ref}")
                if source.get("sha256") is not None and not _is_sha256(source.get("sha256")):
                    errors.append(f"evidence {source_id} sha256 is invalid")
                elif source.get("sha256") is not None and run_dir is not None and _nonempty(ref):
                    artifact = _artifact_path(run_dir, ref)
                    if artifact is not None and sha256_file(artifact) != source["sha256"]:
                        errors.append(f"evidence {source_id} sha256 does not match artifact")
            if strength in {"confirmed", "proven"}:
                independence_keys = {
                    source.get("independence_key").strip()
                    for source in sources
                    if isinstance(source, dict) and _nonempty(source.get("independence_key"))
                }
                artifact_files = {
                    source.get("artifact_ref", "").split("#", 1)[0]
                    for source in sources
                    if isinstance(source, dict) and _nonempty(source.get("artifact_ref"))
                }
                if len(independence_keys) < 2 or len(artifact_files) < 2:
                    errors.append(
                        f"item {item_id} {strength} evidence requires two independent keys and files"
                    )
                if any(
                    not isinstance(source, dict) or not _is_sha256(source.get("sha256"))
                    for source in sources
                ):
                    errors.append(f"item {item_id} {strength} evidence requires artifact sha256")
            if claim in RUNTIME_CLAIMS:
                identity_hashes = {
                    subject_identities.get(ref, {}).get(field)
                    for ref in refs
                    for field in ("sha256", "executable_sha256", "output_sha256")
                    if _is_sha256(subject_identities.get(ref, {}).get(field))
                }
                runtime_sources = [
                    source
                    for source in sources
                    if isinstance(source, dict) and source.get("kind") in RUNTIME_EVIDENCE_KINDS
                ]
                if not runtime_sources:
                    errors.append(f"runtime/release claim {item_id} requires runtime evidence")
                elif not any(
                    _is_sha256(source.get("sha256"))
                    and source.get("sha256") not in identity_hashes
                    for source in runtime_sources
                ):
                    errors.append(
                        f"runtime/release claim {item_id} requires independently hashed runtime evidence"
                    )
            if strength == "proven":
                basis = item.get("proven_basis")
                runtime_refs = basis.get("runtime_subject_refs", []) if isinstance(basis, dict) else []
                if not runtime_refs or any(
                    subject_types.get(ref) not in {"process", "session", "external_service"}
                    for ref in runtime_refs
                ):
                    errors.append(f"item {item_id} proven_basis requires identified runtime subjects")
                if any(ref not in refs for ref in runtime_refs):
                    errors.append(
                        f"item {item_id} proven_basis runtime subjects must belong to item subject_refs"
                    )
                if not any(
                    isinstance(source, dict)
                    and source.get("kind")
                    in {"runtime", "live", "process", "session", "external", "business_canary"}
                    for source in sources
                ):
                    errors.append(f"item {item_id} proven evidence requires an independent runtime source")

    relation_types = {
        "built_from": ({"build"}, {"source"}),
        "produced_by": ({"artifact"}, {"build"}),
        "installed_from": ({"installation"}, {"artifact"}),
        "launched_from": ({"process"}, {"installation", "artifact", "build"}),
        "connected_to": ({"session"}, {"process", "external_service"}),
    }
    for relation in relation_rows:
        relation_id = f"{relation.get('from')}->{relation.get('to')}"
        expected = relation_types.get(relation.get("type"))
        if expected is not None:
            actual_from = subject_types.get(relation.get("from"))
            actual_to = subject_types.get(relation.get("to"))
            if actual_from not in expected[0] or actual_to not in expected[1]:
                errors.append(
                    f"relation {relation_id} has invalid subject types for {relation.get('type')}"
                )
        for evidence_id in relation.get("evidence_refs", []):
            if evidence_id not in evidence_ids:
                errors.append(f"relation {relation_id} references unknown evidence {evidence_id}")
            elif not {relation.get("from"), relation.get("to")}.issubset(
                evidence_subject_refs.get(evidence_id, set())
            ):
                errors.append(
                    f"relation {relation_id} evidence {evidence_id} must be bound to both relation subjects"
                )

    if isinstance(subjects, list):
        for subject in subjects:
            if not isinstance(subject, dict) or subject.get("type") != "build":
                continue
            subject_id = subject.get("id")
            identity = subject.get("identity", {})
            source_ref = identity.get("source_ref") if isinstance(identity, dict) else None
            if not any(
                relation.get("type") == "built_from"
                and relation.get("from") == subject_id
                and relation.get("to") == source_ref
                for relation in relation_rows
            ):
                errors.append(
                    f"build subject {subject_id} source_ref must match an exact built_from relation"
                )

    for subject_id, subject_type in subject_types.items():
        identity_field = {
            "artifact": "sha256",
            "installation": "installed_executable_sha256",
        }.get(subject_type)
        if identity_field is None:
            continue
        artifact_hash = subject_identities.get(subject_id, {}).get(identity_field)
        if not any(
            subject_id in refs and evidence_sha256.get(evidence_id) == artifact_hash
            for evidence_id, refs in evidence_subject_refs.items()
        ):
            errors.append(
                f"{subject_type} subject {subject_id} identity {identity_field} lacks matching evidence"
            )

    relation_targets: dict[tuple[str, str], set[str]] = defaultdict(set)
    for relation in relation_rows:
        relation_targets[(relation.get("type"), relation.get("from"))].add(relation.get("to"))

    def candidate_chain_is_closed(runtime_subject_id: str) -> bool:
        source_aware = document.get("mode") in {
            "whitebox",
            "hybrid",
        } or document.get("source_impact_ref") is not None
        runtime_type = subject_types.get(runtime_subject_id)
        if runtime_type == "session" and subject_identities.get(runtime_subject_id, {}).get(
            "readiness"
        ) != "ready":
            return False
        process_ids = {runtime_subject_id} if runtime_type == "process" else set()
        if runtime_type == "session":
            process_ids = {
                target
                for target in relation_targets.get(("connected_to", runtime_subject_id), set())
                if subject_types.get(target) == "process"
            }
        for process_id in process_ids:
            process_hash = subject_identities.get(process_id, {}).get("executable_sha256")
            process_hash_is_bound = any(
                process_id in refs and evidence_sha256.get(evidence_id) == process_hash
                for evidence_id, refs in evidence_subject_refs.items()
            )
            if not process_hash_is_bound:
                continue
            origins = relation_targets.get(("launched_from", process_id), set())
            artifact_paths: list[tuple[str, bool]] = [
                (
                    origin,
                    process_hash == subject_identities.get(origin, {}).get("sha256"),
                )
                for origin in origins
                if subject_types.get(origin) == "artifact"
            ]
            for installation_id in {
                origin for origin in origins if subject_types.get(origin) == "installation"
            }:
                installed_hash = subject_identities.get(installation_id, {}).get(
                    "installed_executable_sha256"
                )
                install_hash_is_bound = any(
                    installation_id in refs
                    and evidence_sha256.get(evidence_id) == installed_hash
                    for evidence_id, refs in evidence_subject_refs.items()
                )
                if installed_hash != process_hash or not install_hash_is_bound:
                    continue
                artifact_paths.extend(
                    (target, True)
                    for target in relation_targets.get(("installed_from", installation_id), set())
                    if subject_types.get(target) == "artifact"
                )
            for artifact_id, executable_matches in artifact_paths:
                artifact_hash = subject_identities.get(artifact_id, {}).get("sha256")
                hash_is_bound = any(
                    artifact_id in refs and evidence_sha256.get(evidence_id) == artifact_hash
                    for evidence_id, refs in evidence_subject_refs.items()
                )
                if not hash_is_bound:
                    continue
                if not source_aware:
                    if executable_matches:
                        return True
                for build_id in relation_targets.get(("produced_by", artifact_id), set()):
                    if subject_types.get(build_id) != "build":
                        continue
                    if subject_identities.get(build_id, {}).get("output_sha256") != artifact_hash:
                        continue
                    if not executable_matches:
                        continue
                    source_ref = subject_identities.get(build_id, {}).get("source_ref")
                    if source_ref in relation_targets.get(("built_from", build_id), set()):
                        return True
        return False

    summary = document.get("summary")
    if not isinstance(summary, dict):
        errors.append("summary must be an object")
    else:
        for key, value in actual.items():
            if summary.get(key) != value:
                errors.append(f"summary.{key}={summary.get(key)} does not match actual {value}")
        for key, value in pass_breakdown.items():
            if key in summary and summary.get(key) != value:
                errors.append(f"summary.{key}={summary.get(key)} does not match actual {value}")

    coverage = document.get("coverage_by_lane")
    if not isinstance(coverage, dict):
        errors.append("coverage_by_lane must be an object")
    else:
        missing_lanes = COVERAGE_LANES - set(coverage)
        if missing_lanes:
            errors.append(f"coverage_by_lane missing lanes: {', '.join(sorted(missing_lanes))}")
        for lane, row in coverage.items():
            if lane not in COVERAGE_LANES:
                errors.append(f"unsupported coverage lane {lane}")
            if not isinstance(row, dict):
                errors.append(f"coverage lane {lane} must be an object")
                continue
            numerator, denominator, pct = row.get("numerator"), row.get("denominator"), row.get("pct")
            if type(numerator) is not int or type(denominator) is not int:
                errors.append(f"coverage lane {lane} requires integer numerator/denominator")
                continue
            if type(pct) not in {int, float} or not math.isfinite(pct):
                errors.append(f"coverage lane {lane} requires finite numeric pct")
                continue
            if denominator < 0 or numerator < 0 or numerator > denominator:
                errors.append(f"coverage lane {lane} has invalid numerator/denominator")
            expected = 0.0 if denominator == 0 else round(numerator * 100.0 / denominator, 6)
            if abs(pct - expected) > 0.0001:
                errors.append(f"coverage lane {lane}.pct is not reproducible")
            refs = row.get("subject_refs")
            if not isinstance(refs, list) or any(ref not in subject_ids for ref in refs):
                errors.append(f"coverage lane {lane} has invalid subject_refs")
                refs = []
            if not _nonempty(row.get("tool")):
                errors.append(f"coverage lane {lane} requires tool")
            disposition = row.get("disposition")
            item_refs = row.get("item_refs")
            coverage_evidence_refs = row.get("evidence_refs")
            if not isinstance(item_refs, list) or any(ref not in item_ids for ref in item_refs):
                errors.append(f"coverage lane {lane} has invalid item_refs")
                item_refs = []
            if not isinstance(coverage_evidence_refs, list) or any(
                ref not in evidence_ids for ref in coverage_evidence_refs
            ):
                errors.append(f"coverage lane {lane} has invalid evidence_refs")
                coverage_evidence_refs = []
            if disposition == "measured":
                if denominator <= 0 or not item_refs or not coverage_evidence_refs:
                    errors.append(
                        f"measured coverage lane {lane} requires denominator, item_refs, and evidence_refs"
                    )
                referenced_items = [
                    item
                    for item in items or []
                    if isinstance(item, dict) and item.get("id") in item_refs
                ]
                referenced_item_evidence = {
                    source.get("id")
                    for item in referenced_items
                    for source in item.get("evidence_sources", [])
                    if isinstance(source, dict)
                }
                referenced_item_subjects = {
                    ref for item in referenced_items for ref in item.get("subject_refs", [])
                }
                if not set(coverage_evidence_refs).issubset(referenced_item_evidence):
                    errors.append(
                        f"coverage lane {lane} evidence_refs must belong to its item_refs"
                    )
                if not set(refs or []).issubset(referenced_item_subjects):
                    errors.append(
                        f"coverage lane {lane} subject_refs must belong to its item_refs"
                    )
            elif disposition == "not_applicable":
                if numerator != 0 or denominator != 0 or item_refs or coverage_evidence_refs:
                    errors.append(f"not_applicable coverage lane {lane} must be empty")
                if not _nonempty(row.get("reason")):
                    errors.append(f"not_applicable coverage lane {lane} requires reason")
            else:
                errors.append(f"coverage lane {lane} has unsupported disposition")

    source_ref = document.get("source_impact_ref")
    if source_ref is not None:
        if not isinstance(source_ref, dict) or not _nonempty(source_ref.get("artifact_ref")):
            errors.append("source_impact_ref requires artifact_ref")
        elif run_dir is not None:
            impact_artifact = _artifact_path(run_dir, source_ref["artifact_ref"])
            if impact_artifact is None:
                errors.append("source_impact_ref artifact is missing or outside run dir")
            elif _is_sha256(source_ref.get("sha256")) and sha256_file(impact_artifact) != source_ref["sha256"]:
                errors.append("source_impact_ref sha256 does not match artifact")
        if isinstance(source_ref, dict) and not _is_sha256(source_ref.get("sha256")):
            errors.append("source_impact_ref requires sha256")

    gates = document.get("gates")
    gate_ids = _unique_ids(gates, "id", "gates", errors)
    if isinstance(gates, list):
        item_by_id = {
            item.get("id"): item for item in items or [] if isinstance(item, dict) and _nonempty(item.get("id"))
        }
        for gate in gates:
            if not isinstance(gate, dict):
                continue
            if gate.get("verdict") not in {"pass", "fail", "blocked", "skip", "not_applicable"}:
                errors.append(f"gate {gate.get('id')} has unsupported verdict")
            for item_id in gate.get("item_ids", []):
                if item_id not in item_ids:
                    errors.append(f"gate {gate.get('id')} references unknown item {item_id}")
            for evidence_id in gate.get("evidence_refs", []):
                if evidence_id not in evidence_ids:
                    errors.append(f"gate {gate.get('id')} references unknown evidence {evidence_id}")
            referenced_items = [
                item_by_id[item_id]
                for item_id in gate.get("item_ids", [])
                if item_id in item_by_id
            ]
            if gate.get("verdict") == "pass":
                if not referenced_items or not gate.get("evidence_refs"):
                    errors.append(f"pass gate {gate.get('id')} requires item_ids and evidence_refs")
                if any(
                    normalize_status(item.get("status"))
                    not in {"pass", "pass_with_caveat", "pass_known_legacy_behavior"}
                    for item in referenced_items
                ):
                    errors.append(f"pass gate {gate.get('id')} cannot reference non-pass items")
            gate_evidence_ids = {
                source.get("id")
                for item in referenced_items
                for source in item.get("evidence_sources", [])
                if isinstance(source, dict)
            }
            if any(ref not in gate_evidence_ids for ref in gate.get("evidence_refs", [])):
                errors.append(f"gate {gate.get('id')} evidence_refs must belong to its item_ids")
            gate_subject_types = {
                subject_types.get(ref)
                for item in referenced_items
                for ref in item.get("subject_refs", [])
            }
            missing_required_types = set(gate.get("required_subject_types", [])) - gate_subject_types
            if missing_required_types:
                errors.append(
                    f"gate {gate.get('id')} lacks required item subject types: "
                    + ", ".join(sorted(missing_required_types))
                )

    input_refs = document.get("input_refs")
    input_documents: dict[str, Any] = {}
    trusted_profile_document: dict[str, Any] | None = None
    strategy_document: dict[str, Any] | None = None
    if document.get("objective") != "legacy_compatibility" and not isinstance(input_refs, dict):
        errors.append("non-legacy results require hash-bound input_refs")
    if isinstance(input_refs, dict):
        for name, reference in input_refs.items():
            if not isinstance(reference, dict) or not _nonempty(reference.get("artifact_ref")):
                errors.append(f"input_refs.{name} requires artifact_ref")
                continue
            artifact = _artifact_path(run_dir, reference["artifact_ref"]) if run_dir else None
            if artifact is None:
                errors.append(f"input_refs.{name} artifact is missing or outside run dir")
                continue
            if not _is_sha256(reference.get("sha256")) or sha256_file(artifact) != reference.get(
                "sha256"
            ):
                errors.append(f"input_refs.{name} sha256 does not match artifact")
                continue
            try:
                input_documents[name] = load_json(artifact)
            except (OSError, ValueError) as exc:
                errors.append(f"input_refs.{name} is invalid JSON: {exc}")
        profile_document = input_documents.get("project_profile")
        if profile_document is not None:
            errors.extend(
                f"input project_profile: {error}"
                for error in validate("project-profile", profile_document)
            )
        if document.get("objective") != "legacy_compatibility":
            configured_profile = trusted_profile_path
            if configured_profile is None and os.environ.get("BETTER_TEST_TRUSTED_PROFILE"):
                configured_profile = Path(os.environ["BETTER_TEST_TRUSTED_PROFILE"])
            if configured_profile is None:
                errors.append("non-legacy results require an external trusted project profile")
            else:
                try:
                    resolved_profile = configured_profile.resolve(strict=True)
                    loaded_profile = load_json(resolved_profile)
                except (OSError, ValueError) as exc:
                    errors.append(f"trusted project profile cannot be loaded: {exc}")
                else:
                    if isinstance(loaded_profile, dict):
                        trusted_profile_document = loaded_profile
                    if run_dir is not None:
                        try:
                            resolved_profile.relative_to(run_dir.resolve())
                        except ValueError:
                            pass
                        else:
                            errors.append(
                                "trusted project profile must be external to the run directory"
                            )
                    errors.extend(
                        f"trusted project_profile: {error}"
                        for error in validate("project-profile", loaded_profile)
                    )
                    input_profile_ref = input_refs.get("project_profile", {})
                    input_profile_artifact = _artifact_path(
                        run_dir, input_profile_ref.get("artifact_ref", "")
                    ) if run_dir else None
                    if (
                        input_profile_artifact is None
                        or sha256_file(input_profile_artifact) != sha256_file(resolved_profile)
                    ):
                        errors.append("input project_profile differs from external trusted profile")
        policy_profile_document = (
            trusted_profile_document
            if isinstance(trusted_profile_document, dict)
            else profile_document
        )
        profile_features = (
            policy_profile_document.get("features", {})
            if isinstance(policy_profile_document, dict)
            else {}
        )
        hybrid_enabled = profile_features.get("hybrid_testing") is True
        if profile_features.get("results_v4") == "off":
            errors.append("trusted project profile disables results v4")
        capabilities_document = input_documents.get("capabilities")
        available: set[str] = set()
        declared_provider: dict[str, Any] | None = None
        if capabilities_document is not None:
            errors.extend(
                f"input capabilities: {error}"
                for error in validate_capabilities(capabilities_document)
            )
            profile_providers = {
                provider.get("id"): provider
                for provider in (
                    policy_profile_document.get("providers", [])
                    if isinstance(policy_profile_document, dict)
                    else []
                )
                if isinstance(provider, dict) and _nonempty(provider.get("id"))
            }
            capability_provider = capabilities_document.get("provider", {})
            declared_provider = profile_providers.get(capability_provider.get("id"))
            if not isinstance(declared_provider, dict):
                errors.append("capabilities provider is not declared by project profile")
            else:
                trust = declared_provider.get("trust", {})
                if capability_provider.get("version") != trust.get("version"):
                    errors.append("capabilities provider version differs from profile trust")
                if capability_provider.get("implementation_sha256") != trust.get("sha256"):
                    errors.append("capabilities provider implementation differs from profile trust")
                declared_capabilities = set(declared_provider.get("capabilities", []))
                reported_available = {
                    capability.get("name")
                    for capability in capabilities_document.get("capabilities", [])
                    if isinstance(capability, dict)
                    and capability.get("status") == "available"
                    and capability.get("name") in CAPABILITY_IDS
                }
                if not reported_available.issubset(declared_capabilities):
                    errors.append("available capabilities exceed profile provider declaration")
            available = {
                capability.get("name")
                for capability in capabilities_document.get("capabilities", [])
                if isinstance(capability, dict)
                and capability.get("status") == "available"
                and capability.get("name") in CAPABILITY_IDS
            }
            unavailable = {
                capability.get("name")
                for capability in capabilities_document.get("capabilities", [])
                if isinstance(capability, dict)
                and capability.get("name") in CAPABILITY_IDS
                and capability.get("status") != "available"
            }
            if not unavailable.issubset(set(document.get("missing_capabilities", []))):
                errors.append("missing_capabilities omits unavailable input capabilities")
        strategy_document = input_documents.get("strategy")
        if not isinstance(strategy_document, dict):
            if document.get("objective") != "legacy_compatibility":
                errors.append("input_refs.strategy must resolve to a strategy object")
        else:
            if strategy_document.get("schema_version") != 1:
                errors.append("strategy schema_version must be 1")
            if not isinstance(strategy_document.get("required_lanes"), list) or any(
                lane not in COVERAGE_LANES
                for lane in strategy_document.get("required_lanes", [])
            ):
                errors.append("strategy required_lanes is invalid")
            if not isinstance(strategy_document.get("required_gates"), list) or any(
                not _nonempty(gate_id)
                for gate_id in strategy_document.get("required_gates", [])
            ):
                errors.append("strategy required_gates is invalid")
            if not isinstance(strategy_document.get("missing_capabilities"), list) or any(
                capability not in CAPABILITY_IDS
                for capability in strategy_document.get("missing_capabilities", [])
            ):
                errors.append("strategy missing_capabilities is invalid")
            if strategy_document.get("normalized_objective") != document.get("objective"):
                errors.append("strategy normalized_objective differs from results objective")
            if strategy_document.get("mode") != document.get("mode"):
                errors.append("strategy mode differs from results mode")
            if capabilities_document is not None:
                effective_available = set(available)
                if not hybrid_enabled:
                    effective_available -= {"source-map", "source-impact"}
                derived_mode = derive_mode(effective_available, hybrid_enabled)
                if strategy_document.get("mode") != derived_mode:
                    errors.append("strategy mode differs from capability-derived mode")
                if strategy_document.get("feature_flags") != profile_features:
                    errors.append("strategy feature_flags differ from trusted project profile")
                mutation_policy = (
                    policy_profile_document.get("evidence_policy", {})
                    .get("mutation", {})
                    .get("required_for", [])
                    if isinstance(policy_profile_document, dict)
                    else []
                )
                if strategy_document.get("mutation_required_for") != mutation_policy:
                    errors.append("strategy mutation policy differs from trusted project profile")
                impact_mutation_triggers = (
                    input_documents.get("source_impact", {}).get("mutation_triggers", [])
                    if isinstance(input_documents.get("source_impact"), dict)
                    else []
                )
                matched_mutation_triggers = sorted(
                    set(impact_mutation_triggers) & set(mutation_policy)
                )
                if strategy_document.get("mutation_required") is not bool(
                    matched_mutation_triggers
                ) or sorted(strategy_document.get("mutation_triggers", [])) != matched_mutation_triggers:
                    errors.append("strategy mutation decision differs from policy and impact")
                normalized_objective = strategy_document.get("normalized_objective")
                if normalized_objective in OBJECTIVE_REQUIRED_CAPABILITIES:
                    reported_capabilities = {
                        capability.get("name")
                        for capability in capabilities_document.get("capabilities", [])
                        if isinstance(capability, dict)
                    }
                    omitted_rows = (
                        OBJECTIVE_REQUIRED_CAPABILITIES[normalized_objective]
                        - reported_capabilities
                    )
                    if omitted_rows:
                        errors.append(
                            "capability input omits objective-required rows: "
                            + ", ".join(sorted(omitted_rows))
                        )
                    derived_missing = sorted(
                        OBJECTIVE_REQUIRED_CAPABILITIES[normalized_objective]
                        - effective_available
                    )
                    if sorted(strategy_document.get("missing_capabilities", [])) != derived_missing:
                        errors.append("strategy missing_capabilities differs from capability-derived set")
                    derived_ceiling = derive_claim_ceiling(
                        normalized_objective, effective_available
                    )
                    if strategy_document.get("max_claim_scope") != derived_ceiling:
                        errors.append("strategy max_claim_scope differs from capability-derived ceiling")
            strategy_max = strategy_document.get("max_claim_scope")
            if strategy_max not in CLAIM_RANK or (
                document.get("max_claim_scope") in CLAIM_RANK
                and CLAIM_RANK[document["max_claim_scope"]] > CLAIM_RANK[strategy_max]
            ):
                errors.append("results max_claim_scope exceeds strategy ceiling")
            if not set(strategy_document.get("missing_capabilities", [])).issubset(
                set(document.get("missing_capabilities", []))
            ):
                errors.append("results omits strategy missing_capabilities")
            if not set(strategy_document.get("required_lanes", [])).issubset(
                set(document.get("coverage_by_lane", {}))
            ):
                errors.append("results omits strategy required_lanes")
            for lane in strategy_document.get("required_lanes", []):
                lane_coverage = document.get("coverage_by_lane", {}).get(lane, {})
                if lane_coverage.get("disposition") != "measured":
                    errors.append(f"strategy required lane is not measured: {lane}")
            normalized_gate_ids = {str(gate_id).casefold() for gate_id in gate_ids}
            if not {
                str(gate_id).casefold()
                for gate_id in strategy_document.get("required_gates", [])
            }.issubset(normalized_gate_ids):
                errors.append("results omits strategy required_gates")
        source_aware = document.get("mode") in {"whitebox", "hybrid"}
        if source_aware:
            for name, kind in (
                ("source_map", "source-map"),
                ("source_impact", "source-impact"),
            ):
                artifact_document = input_documents.get(name)
                if artifact_document is None:
                    errors.append(f"source-aware results require input_refs.{name}")
                else:
                    errors.extend(
                        f"input {name}: {error}"
                        for error in validate(kind, artifact_document)
                    )
            if input_refs.get("source_impact") != document.get("source_impact_ref"):
                errors.append("source_impact_ref must equal input_refs.source_impact")
            source_map_document = input_documents.get("source_map")
            source_impact_document = input_documents.get("source_impact")
            if isinstance(source_map_document, dict) and isinstance(source_impact_document, dict):
                if isinstance(declared_provider, dict):
                    map_provider = source_map_document.get("provider", {})
                    trust = declared_provider.get("trust", {})
                    if map_provider.get("id") != declared_provider.get("id"):
                        errors.append("source map provider differs from capabilities provider")
                    if map_provider.get("version") != trust.get("version"):
                        errors.append("source map provider version differs from profile trust")
                    generation_binding = source_map_document.get("provider_metadata", {}).get(
                        "generation_binding", {}
                    )
                    if generation_binding.get("provider_implementation_sha256") != trust.get(
                        "sha256"
                    ):
                        errors.append("source map provider implementation differs from profile trust")
                mapped_source = source_map_document.get("source", {})
                mapped_source_id = mapped_source.get("subject_id")
                if mapped_source_id not in subject_ids or mapped_source.get(
                    "identity"
                ) != subject_identities.get(mapped_source_id):
                    errors.append("source map identity differs from results source subject")
                if source_impact_document.get("source_map_sha256") != input_refs.get(
                    "source_map", {}
                ).get("sha256"):
                    errors.append("source impact does not bind input source map sha256")
                impact_gates = {
                    str(gate_id).casefold()
                    for gate_id in source_impact_document.get("required_gates", [])
                }
                result_gates = {str(gate_id).casefold() for gate_id in gate_ids}
                strategy_gates = {
                    str(gate_id).casefold()
                    for gate_id in (
                        strategy_document.get("required_gates", [])
                        if isinstance(strategy_document, dict)
                        else []
                    )
                }
                if not impact_gates.issubset(result_gates):
                    errors.append("results omits source-impact required_gates")
                if not impact_gates.issubset(strategy_gates):
                    errors.append("strategy omits source-impact required_gates")
                impact_lanes = set(source_impact_document.get("required_lanes", []))
                strategy_lanes = set(
                    strategy_document.get("required_lanes", [])
                    if isinstance(strategy_document, dict)
                    else []
                )
                if not impact_lanes.issubset(strategy_lanes):
                    errors.append("strategy omits source-impact required_lanes")
                selections = source_impact_document.get("selections", {})
                selection_ids = {
                    row.get("id")
                    for bucket in ("required", "recommended", "excluded")
                    for row in selections.get(bucket, [])
                    if isinstance(row, dict)
                }
                required_selection_ids = {
                    row.get("id")
                    for row in selections.get("required", [])
                    if isinstance(row, dict)
                }
                mutation_selection_ids = {
                    row.get("id")
                    for row in selections.get("required", [])
                    if isinstance(row, dict) and row.get("kind") == "mutation"
                }
                covered_required: set[str] = set()
                passed_mutation: set[str] = set()
                closed_statuses = {
                    "pass",
                    "pass_with_caveat",
                    "pass_known_legacy_behavior",
                    "fail",
                    "partial_fail",
                    "blocked",
                    "skip",
                }
                for item in items or []:
                    if not isinstance(item, dict):
                        continue
                    refs = item.get("selection_refs", [])
                    if not isinstance(refs, list) or any(ref not in selection_ids for ref in refs):
                        errors.append(f"item {item.get('id')} has invalid selection_refs")
                        continue
                    if normalize_status(item.get("status")) in closed_statuses:
                        covered_required.update(set(refs) & required_selection_ids)
                    if normalize_status(item.get("status")) in {
                        "pass",
                        "pass_with_caveat",
                        "pass_known_legacy_behavior",
                    }:
                        passed_mutation.update(set(refs) & mutation_selection_ids)
                missing_selections = required_selection_ids - covered_required
                if missing_selections:
                    errors.append(
                        "required source-impact selections lack closed result items: "
                        + ", ".join(sorted(missing_selections))
                    )
                if (
                    mutation_selection_ids - passed_mutation
                    and document.get("max_claim_scope") in CLAIM_RANK
                    and CLAIM_RANK[document["max_claim_scope"]]
                    >= CLAIM_RANK["source_correctness"]
                ):
                    errors.append(
                        "source_correctness claim requires every policy mutation selection to pass"
                    )

    readiness = document.get("release_readiness")
    missing_capabilities = document.get("missing_capabilities")
    if not isinstance(missing_capabilities, list) or any(
        capability not in CAPABILITY_IDS for capability in missing_capabilities
    ):
        errors.append("missing_capabilities contains unsupported capability ids")
        missing_capabilities = []
    elif len(missing_capabilities) != len(set(missing_capabilities)):
        errors.append("missing_capabilities must not contain duplicates")
    if not isinstance(readiness, dict):
        errors.append("release_readiness must be an object")
    else:
        verdict = readiness.get("verdict")
        if verdict not in {"go", "no-go", "blocked", "not_applicable"}:
            errors.append("release_readiness.verdict is unsupported")
        if not _nonempty(readiness.get("reason")):
            errors.append("release_readiness.reason is required")
        if verdict == "go":
            if document.get("objective") != "release_decision":
                errors.append("release GO requires objective release_decision")
            profile_document = (
                trusted_profile_document
                if isinstance(trusted_profile_document, dict)
                else input_documents.get("project_profile")
            )
            fixed_gates = (
                profile_document.get("extensions", {}).get("release_fixed_gates", [])
                if isinstance(profile_document, dict)
                else []
            )
            gate_verdicts = {
                str(gate.get("id")).casefold(): gate.get("verdict")
                for gate in gates or []
                if isinstance(gate, dict)
            }
            missing_or_unpassed_fixed = [
                gate_id
                for gate_id in fixed_gates
                if gate_verdicts.get(str(gate_id).casefold()) != "pass"
            ]
            if missing_or_unpassed_fixed:
                errors.append("release GO requires every project fixed gate to pass")
            required_strategy_gates = (
                strategy_document.get("required_gates", [])
                if isinstance(strategy_document, dict)
                else []
            )
            if any(
                gate_verdicts.get(str(gate_id).casefold()) != "pass"
                for gate_id in required_strategy_gates
            ):
                errors.append("release GO requires every strategy required gate to pass")
            required_claim_scopes = (
                profile_document.get("evidence_policy", {}).get(
                    "release_required_claim_scopes", []
                )
                if isinstance(profile_document, dict)
                else []
            )
            passed_gate_ids = {
                item_id
                for gate in gates or []
                if isinstance(gate, dict) and gate.get("verdict") == "pass"
                for item_id in gate.get("item_ids", [])
            }
            passed_items_by_scope = {
                item.get("claim_scope"): item
                for item in items or []
                if isinstance(item, dict)
                and item.get("id") in passed_gate_ids
                and normalize_status(item.get("status"))
                in {"pass", "pass_with_caveat", "pass_known_legacy_behavior"}
            }
            missing_policy_scopes = set(required_claim_scopes) - set(passed_items_by_scope)
            if missing_policy_scopes:
                errors.append(
                    "release GO lacks policy-required passed claim scopes: "
                    + ", ".join(sorted(missing_policy_scopes))
                )
            if "business_canary" in passed_items_by_scope and passed_items_by_scope[
                "business_canary"
            ].get("test_kind") != "business_canary":
                errors.append("business_canary claim requires business_canary test_kind")
            if "write_lifecycle" in passed_items_by_scope and passed_items_by_scope[
                "write_lifecycle"
            ].get("test_kind") != "write_lifecycle":
                errors.append("write_lifecycle claim requires write_lifecycle test_kind")
            release_capabilities = {
                "runtime-probe",
                "artifact-identity",
                "process-identity",
                "session-readiness",
                "typed-subject-identity",
            }
            if release_capabilities.intersection(missing_capabilities):
                errors.append("release GO cannot declare missing release capabilities")
            if actual["failed"] or actual["blocked"]:
                errors.append("release GO cannot contain failed or blocked items")
            if actual["skipped"] or actual["excluded"] or actual["pending"] or actual["partial"]:
                errors.append("release GO cannot contain skipped, excluded, pending, or partial items")
            if isinstance(gates, list) and any(
                gate.get("verdict") in {"fail", "blocked"} for gate in gates if isinstance(gate, dict)
            ):
                errors.append("release GO cannot contain failed or blocked gates")
            if isinstance(gates, list) and any(
                gate.get("verdict") == "skip" for gate in gates if isinstance(gate, dict)
            ):
                errors.append("release GO cannot contain skipped gates")
            if not set(subject_types.values()).intersection({"process", "session"}):
                errors.append("release GO requires process or session subject evidence")
            runtime_gate_closed = False
            runtime_gate_subjects: set[str] = set()
            if isinstance(gates, list) and isinstance(items, list):
                item_by_id = {
                    item.get("id"): item
                    for item in items
                    if isinstance(item, dict) and _nonempty(item.get("id"))
                }
                for gate in gates:
                    if not isinstance(gate, dict) or gate.get("verdict") != "pass":
                        continue
                    for item_id in gate.get("item_ids", []):
                        item = item_by_id.get(item_id)
                        if not isinstance(item, dict):
                            continue
                        item_types = {subject_types.get(ref) for ref in item.get("subject_refs", [])}
                        if (
                            normalize_status(item.get("status"))
                            in {"pass", "pass_with_caveat", "pass_known_legacy_behavior"}
                            and item.get("claim_scope") in RUNTIME_CLAIMS
                            and item_types.intersection({"process", "session"})
                        ):
                            runtime_gate_closed = True
                            runtime_gate_subjects.update(
                                ref
                                for ref in item.get("subject_refs", [])
                                if subject_types.get(ref) in {"process", "session"}
                            )
                            break
                    if runtime_gate_closed:
                        break
            if not runtime_gate_closed:
                errors.append("release GO requires a passed runtime-claim item bound to a passed gate")
            if any(
                subject_types.get(ref) == "session"
                and subject_identities.get(ref, {}).get("readiness") != "ready"
                for ref in runtime_gate_subjects
            ):
                errors.append("release GO requires every bound session to be ready")
            elif not any(candidate_chain_is_closed(ref) for ref in runtime_gate_subjects):
                errors.append(
                    "release GO requires a candidate identity chain from runtime through artifact/build to source"
                )
            if document.get("max_claim_scope") != "release_gate":
                errors.append("release GO requires max_claim_scope release_gate")
            if pass_breakdown["passed_with_caveat"] or pass_breakdown["passed_known_legacy_behavior"]:
                override = readiness.get("override")
                if not isinstance(override, dict) or not all(
                    _nonempty(override.get(field)) for field in ("approved_by", "reason")
                ) or not is_timestamp(override.get("approved_at")):
                    errors.append("release GO with caveat/legacy pass requires a complete override")
    max_claim = document.get("max_claim_scope")
    if max_claim not in CLAIM_RANK:
        errors.append("max_claim_scope is unsupported")
    if max_claim in RUNTIME_CLAIMS and not set(subject_types.values()).intersection(
        {"process", "session", "external_service"}
    ):
        errors.append("max_claim_scope exceeds available runtime subjects")
    if max_claim in RUNTIME_CLAIMS and {
        "runtime-probe",
        "process-identity",
        "typed-subject-identity",
    }.intersection(missing_capabilities):
        errors.append("max_claim_scope exceeds declared runtime capabilities")
    objective_ceiling = OBJECTIVE_MAX_CLAIM.get(document.get("objective"))
    if (
        max_claim in CLAIM_RANK
        and objective_ceiling in CLAIM_RANK
        and CLAIM_RANK[max_claim] > CLAIM_RANK[objective_ceiling]
    ):
        errors.append(
            f"max_claim_scope {max_claim} exceeds objective ceiling {objective_ceiling}"
        )
    if isinstance(items, list) and max_claim in CLAIM_RANK:
        for item in items:
            if isinstance(item, dict) and item.get("claim_scope") in CLAIM_RANK:
                if CLAIM_RANK[item["claim_scope"]] > CLAIM_RANK[max_claim]:
                    errors.append(f"item {item.get('id')} exceeds max_claim_scope {max_claim}")
        passed_gate_item_ids = {
            item_id
            for gate in gates or []
            if isinstance(gate, dict) and gate.get("verdict") == "pass"
            for item_id in gate.get("item_ids", [])
        }
        supported_claims = [
            item.get("claim_scope")
            for item in items
            if isinstance(item, dict)
            and normalize_status(item.get("status"))
            in {"pass", "pass_with_caveat", "pass_known_legacy_behavior"}
            and item.get("claim_scope") in CLAIM_RANK
            and (
                item.get("claim_scope") != "release_gate"
                or item.get("id") in passed_gate_item_ids
            )
        ]
        supported_rank = max((CLAIM_RANK[claim] for claim in supported_claims), default=0)
        if CLAIM_RANK[max_claim] > supported_rank:
            errors.append(f"max_claim_scope {max_claim} exceeds passed evidence claim ceiling")
    return errors


VALIDATORS: dict[str, Callable[[Any, Path | None], list[str]]] = {
    "project-profile": validate_project_profile,
    "capabilities": validate_capabilities,
    "source-map": validate_source_map,
    "source-impact": validate_source_impact,
    "results-v4": validate_results_v4,
}


def validate(kind: str, document: Any, path: Path | None = None) -> list[str]:
    try:
        validator = VALIDATORS[kind]
    except KeyError as exc:
        raise ValueError(f"unsupported document kind: {kind}") from exc
    errors: list[str] = []
    if kind in {"project-profile", "source-map", "source-impact"}:
        errors.extend(validate_schema_file(kind, document))
    errors.extend(validator(document, path))
    return errors


def canonicalize_results(document: dict[str, Any]) -> dict[str, Any]:
    schema = document.get("schema_version")
    if schema not in {3, 4}:
        raise ValueError("canonicalization supports results schema 3 or 4")
    items: list[dict[str, Any]] = []
    for item in document.get("items", []):
        if schema == 3:
            evidence = item.get("evidence_sources", [])
            provenance = {
                key: item.get(key)
                for key in ("origin_run_id", "origin_status", "classification", "blocker_class")
                if item.get(key) is not None
            }
            if item.get("pre_existing") is True:
                provenance["pre_existing"] = True
            items.append(
                {
                    "id": item.get("id"),
                    "name": item.get("name"),
                    "status": normalize_status(item.get("status")),
                    "assertion_field": item.get("assertion_field"),
                    "assertion_value": item.get("assertion_value"),
                    "evidence_count": len(evidence) if isinstance(evidence, list) else 0,
                    "test_kind": item.get("test_kind", "legacy"),
                    "subject_refs": sorted(item.get("subject_refs", ["legacy:run"])),
                    "claim_scope": item.get("claim_scope", "behavior"),
                    "evidence_strength": item.get("evidence_strength", item.get("evidence_level")),
                    "proven_basis": item.get("proven_basis"),
                    "evidence": sorted(
                        [
                            {
                                "id": source.get("source_id"),
                                "independence_key": source.get("independence_key", "legacy"),
                                "artifact_ref": source.get("artifact_ref"),
                                "kind": source.get("evidence_kind", "legacy"),
                                "sha256": source.get("sha256"),
                            }
                            for source in evidence
                            if isinstance(source, dict)
                        ],
                        key=lambda row: str(row.get("id")),
                    ),
                    "bug_ids": sorted(item.get("bug_ids", [])),
                    "selection_refs": sorted(item.get("selection_refs", [])),
                    "provenance": provenance,
                }
            )
        else:
            assertion = item.get("assertion", {})
            evidence = item.get("evidence_sources", [])
            provider_metadata = item.get("provider_metadata", {})
            provenance = (
                provider_metadata.get("legacy_provenance", {})
                if isinstance(provider_metadata, dict)
                else {}
            )
            items.append(
                {
                    "id": item.get("id"),
                    "name": item.get("name"),
                    "status": normalize_status(item.get("status")),
                    "assertion_field": assertion.get("field") if isinstance(assertion, dict) else None,
                    "assertion_value": assertion.get("value") if isinstance(assertion, dict) else None,
                    "evidence_count": len(evidence) if isinstance(evidence, list) else 0,
                    "test_kind": item.get("test_kind"),
                    "subject_refs": sorted(item.get("subject_refs", [])),
                    "claim_scope": item.get("claim_scope"),
                    "evidence_strength": item.get("evidence_strength"),
                    "proven_basis": item.get("proven_basis"),
                    "evidence": sorted(
                        [
                            {
                                "id": source.get("id"),
                                "independence_key": source.get("independence_key"),
                                "artifact_ref": source.get("artifact_ref"),
                                "kind": source.get("kind"),
                                "sha256": source.get("sha256"),
                            }
                            for source in evidence
                            if isinstance(source, dict)
                        ],
                        key=lambda row: str(row.get("id")),
                    ),
                    "bug_ids": sorted(item.get("bug_ids", [])),
                    "selection_refs": sorted(item.get("selection_refs", [])),
                    "provenance": provenance,
                }
            )
    items.sort(key=lambda row: str(row.get("id")))
    gates: list[dict[str, Any]] = []
    raw_gates = document.get("gate_items", []) if schema == 3 else document.get("gates", [])
    for gate in raw_gates:
        if not isinstance(gate, dict):
            continue
        gates.append(
            {
                "id": gate.get("gate_id") if schema == 3 else gate.get("id"),
                "verdict": gate.get("verdict"),
                "reason": gate.get("reason"),
                "item_ids": sorted(gate.get("item_ids", [])),
                "evidence_refs": sorted(gate.get("evidence_refs", [])),
                "required_subject_types": sorted(
                    gate.get("required_subject_types", ["unknown"] if schema == 3 else [])
                ),
            }
        )
    gates.sort(key=lambda row: str(row.get("id")))
    readiness = document.get("release_readiness", {})
    hybrid = document.get("hybrid", {}) if schema == 3 else {}
    if schema == 3 and not isinstance(hybrid, dict):
        hybrid = {}
    raw_subjects = hybrid.get("subjects", []) if schema == 3 else document.get("subjects", [])
    if schema == 3 and not raw_subjects:
        raw_subjects = [
            {
                "id": "legacy:run",
                "type": "unknown",
                "identity": {"run_id": document.get("run_id")},
            }
        ]
    subject_types = sorted(
        [
            {
                "id": subject.get("id"),
                "type": subject.get("type"),
                "identity": subject.get("identity"),
                "provider_metadata": subject.get("provider_metadata"),
            }
            for subject in raw_subjects
            if isinstance(subject, dict)
        ],
        key=lambda row: str(row.get("id")),
    )
    raw_relations = hybrid.get("relations", []) if schema == 3 else document.get("relations", [])
    relations = sorted(
        [
            {
                "type": relation.get("type"),
                "from": relation.get("from"),
                "to": relation.get("to"),
                "evidence_refs": sorted(relation.get("evidence_refs", [])),
            }
            for relation in raw_relations
            if isinstance(relation, dict)
        ],
        key=lambda row: (str(row.get("type")), str(row.get("from")), str(row.get("to"))),
    )
    if schema == 3:
        typed_coverage = hybrid.get("coverage_by_lane")
        if isinstance(typed_coverage, dict):
            coverage_by_lane = {}
            canonical_item_refs = [row["id"] for row in items if _nonempty(row.get("id"))]
            canonical_evidence_refs = [
                source["id"]
                for row in items
                for source in row.get("evidence", [])
                if _nonempty(source.get("id"))
            ]
            for lane, row in typed_coverage.items():
                if not isinstance(row, dict):
                    continue
                measured = row.get("denominator", 0) > 0
                coverage_by_lane[lane] = {
                    **row,
                    "subject_refs": sorted(row.get("subject_refs", [])),
                    "disposition": row.get("disposition")
                    or ("measured" if measured else "not_applicable"),
                    "item_refs": sorted(
                        row.get("item_refs", canonical_item_refs if measured else [])
                    ),
                    "evidence_refs": sorted(
                        row.get(
                            "evidence_refs",
                            canonical_evidence_refs if measured else [],
                        )
                    ),
                    **(
                        {"reason": row.get("reason") or row.get("conditions") or "not represented"}
                        if not measured
                        else {}
                    ),
                }
        else:
            coverage = document.get("coverage", {})
            tested = coverage.get("tested", 0) if isinstance(coverage, dict) else 0
            reachable = coverage.get("reachable", 0) if isinstance(coverage, dict) else 0
            pct = 0.0 if not reachable else round(tested * 100.0 / reachable, 6)
            subject_refs = [row["id"] for row in subject_types if _nonempty(row.get("id"))]
            coverage_by_lane = {
                lane: {
                    "numerator": tested if lane == "surface" else 0,
                    "denominator": reachable if lane == "surface" else 0,
                    "pct": pct if lane == "surface" else 0.0,
                    "subject_refs": sorted(subject_refs),
                    "tool": "v3-projection",
                    "conditions": (
                        "projected from v3 reachable coverage"
                        if lane == "surface"
                        else "not represented in schema v3"
                    ),
                    "disposition": (
                        "measured" if lane == "surface" and reachable > 0 else "not_applicable"
                    ),
                    "item_refs": (
                        [row["id"] for row in items if _nonempty(row.get("id"))]
                        if lane == "surface" and reachable > 0
                        else []
                    ),
                    "evidence_refs": (
                        [
                            source["id"]
                            for row in items
                            for source in row.get("evidence", [])
                            if _nonempty(source.get("id"))
                        ]
                        if lane == "surface" and reachable > 0
                        else []
                    ),
                    **(
                        {"reason": "not represented in schema v3"}
                        if lane != "surface" or reachable == 0
                        else {}
                    ),
                }
                for lane in sorted(COVERAGE_LANES)
            }
        missing_capabilities = sorted(
            hybrid.get("missing_capabilities", ["typed-subject-identity"])
        )
        source_impact_ref = (
            hybrid.get("artifacts", {}).get("source_impact")
            if isinstance(hybrid.get("artifacts"), dict)
            else None
        )
        hybrid_artifacts = hybrid.get("artifacts", {})
        input_refs = None
        if hybrid.get("objective", "legacy_compatibility") != "legacy_compatibility":
            input_refs = {
                key: hybrid_artifacts[key]
                for key in (
                    "project_profile",
                    "capabilities",
                    "strategy",
                    "source_map",
                    "source_impact",
                )
                if isinstance(hybrid_artifacts, dict) and key in hybrid_artifacts
            }
    else:
        coverage_by_lane = {
            lane: {
                **row,
                "subject_refs": sorted(row.get("subject_refs", [])),
                "item_refs": sorted(row.get("item_refs", [])),
                "evidence_refs": sorted(row.get("evidence_refs", [])),
            }
            for lane, row in document.get("coverage_by_lane", {}).items()
            if isinstance(row, dict)
        }
        missing_capabilities = sorted(document.get("missing_capabilities", []))
        source_impact_ref = document.get("source_impact_ref")
        input_refs = document.get("input_refs")
    normalized_mode = document.get("mode")
    if schema == 3:
        normalized_mode = hybrid.get("mode")
        if normalized_mode not in {"blackbox", "whitebox", "hybrid"}:
            normalized_mode = "blackbox"
    return {
        "version": document.get("version"),
        "run_id": document.get("run_id"),
        "mode": normalized_mode,
        "objective": hybrid.get("objective", "legacy_compatibility") if schema == 3 else document.get("objective"),
        "max_claim_scope": hybrid.get("max_claim_scope", "behavior") if schema == 3 else document.get("max_claim_scope"),
        "summary": document.get("summary"),
        "items": items,
        "gates": gates,
        "subjects": subject_types,
        "relations": relations,
        "coverage_by_lane": coverage_by_lane,
        "missing_capabilities": missing_capabilities,
        "source_impact_ref": source_impact_ref,
        "input_refs": input_refs,
        "release_readiness": readiness if isinstance(readiness, dict) else None,
    }


def semantic_diff(left: dict[str, Any], right: dict[str, Any]) -> list[str]:
    lhs = canonicalize_results(left)
    rhs = canonicalize_results(right)
    if left.get("schema_version") != right.get("schema_version"):
        legacy = left if left.get("schema_version") == 3 else right
        other = rhs if left.get("schema_version") == 3 else lhs
        legacy_canonical = lhs if left.get("schema_version") == 3 else rhs
        legacy_hashes = {
            source.get("source_id"): source.get("sha256")
            for item in legacy.get("items", [])
            if isinstance(item, dict)
            for source in item.get("evidence_sources", [])
            if isinstance(source, dict)
        }
        for item in other.get("items", []):
            for source in item.get("evidence", []):
                if source.get("id") in legacy_hashes and legacy_hashes[source.get("id")] is None:
                    source["sha256"] = None
        for item in legacy_canonical.get("items", []):
            for source in item.get("evidence", []):
                if source.get("id") in legacy_hashes and legacy_hashes[source.get("id")] is None:
                    source["sha256"] = None
    errors: list[str] = []
    for key in (
        "version",
        "run_id",
        "mode",
        "objective",
        "max_claim_scope",
        "summary",
        "items",
        "gates",
        "subjects",
        "relations",
        "coverage_by_lane",
        "missing_capabilities",
        "source_impact_ref",
        "input_refs",
        "release_readiness",
    ):
        if lhs.get(key) != rhs.get(key):
            errors.append(f"canonical field differs: {key}")
    return errors


def v3_to_v4(document: dict[str, Any], run_dir: Path | None = None) -> dict[str, Any]:
    if document.get("schema_version") != 3:
        raise ValueError("input must use schema v3")
    hybrid = document.get("hybrid", {})
    if not isinstance(hybrid, dict):
        hybrid = {}
    subjects = hybrid.get("subjects")
    if not isinstance(subjects, list) or not subjects:
        subjects = [
            {
                "id": "legacy:run",
                "type": "unknown",
                "identity": {"run_id": document.get("run_id")},
            }
        ]
    subject_refs_default = [subject["id"] for subject in subjects if isinstance(subject, dict) and _nonempty(subject.get("id"))]
    items: list[dict[str, Any]] = []
    for item in document.get("items", []):
        status = normalize_status(item.get("status"))
        legacy_provenance = {
            key: item.get(key)
            for key in ("origin_run_id", "origin_status", "classification", "blocker_class")
            if item.get(key) is not None
        }
        if item.get("pre_existing") is True:
            legacy_provenance["pre_existing"] = True
        sources: list[dict[str, Any]] = []
        for source in item.get("evidence_sources", []):
            ref = source.get("artifact_ref")
            artifact = _artifact_path(run_dir, ref) if run_dir is not None and _nonempty(ref) else None
            evidence_hash = source.get("sha256")
            if evidence_hash is None and artifact is not None:
                evidence_hash = sha256_file(artifact)
            sources.append(
                {
                    "id": source.get("source_id"),
                    "independence_key": source.get("independence_key", "legacy"),
                    "artifact_ref": source.get("artifact_ref"),
                    "kind": source.get("evidence_kind", "legacy"),
                    **({"sha256": evidence_hash} if evidence_hash is not None else {}),
                }
            )
        items.append(
            {
                "id": item.get("id"),
                "name": item.get("name"),
                "status": status,
                "test_kind": item.get("test_kind", "legacy"),
                "subject_refs": item.get("subject_refs", subject_refs_default),
                "claim_scope": item.get("claim_scope", "behavior"),
                "evidence_strength": item.get("evidence_strength", item.get("evidence_level")),
                "assertion": {
                    "field": item.get("assertion_field"),
                    "value": item.get("assertion_value"),
                },
                "evidence_sources": sources,
                "bug_ids": item.get("bug_ids", []),
                "selection_refs": item.get("selection_refs", []),
                **({"proven_basis": item["proven_basis"]} if "proven_basis" in item else {}),
                **(
                    {"provider_metadata": {"legacy_provenance": legacy_provenance}}
                    if legacy_provenance
                    else {}
                ),
                **(
                    {
                        "reason": item.get("caveat_reason")
                        or item.get("skip_reason")
                        or item.get("error_detail")
                        or "legacy status"
                    }
                    if status
                    in {
                        "skip",
                        "excluded",
                        "blocked",
                        "pass_with_caveat",
                        "pass_known_legacy_behavior",
                    }
                    else {}
                ),
            }
        )
    coverage = document.get("coverage", {})
    tested = coverage.get("tested", 0) if isinstance(coverage, dict) else 0
    reachable = coverage.get("reachable", 0) if isinstance(coverage, dict) else 0
    pct = 0.0 if not reachable else round(tested * 100.0 / reachable, 6)
    legacy_readiness = document.get("release_readiness")
    if not isinstance(legacy_readiness, dict):
        legacy_readiness = {"verdict": "not_applicable"}
    legacy_verdict = legacy_readiness.get("verdict", "not_applicable")
    readiness = {
        **legacy_readiness,
        "verdict": "blocked" if legacy_verdict == "go" else legacy_verdict,
        "reason": (
            "schema v3 GO was capped because typed runtime identity is unavailable"
            if legacy_verdict == "go"
            else legacy_readiness.get("reason") or "projected from schema v3"
        ),
    }
    hybrid_artifacts = hybrid.get("artifacts", {})
    objective = hybrid.get("objective", "legacy_compatibility")
    input_refs = None
    if objective != "legacy_compatibility":
        input_refs = {
            key: hybrid_artifacts[key]
            for key in (
                "project_profile",
                "capabilities",
                "strategy",
                "source_map",
                "source_impact",
            )
            if isinstance(hybrid_artifacts, dict) and key in hybrid_artifacts
        }
    projected_item_refs = [item["id"] for item in items if _nonempty(item.get("id"))]
    projected_evidence_refs = [
        source["id"]
        for item in items
        for source in item.get("evidence_sources", [])
        if isinstance(source, dict) and _nonempty(source.get("id"))
    ]
    typed_coverage = hybrid.get("coverage_by_lane")
    if isinstance(typed_coverage, dict):
        projected_coverage = {}
        for lane, row in typed_coverage.items():
            if not isinstance(row, dict):
                continue
            measured = row.get("denominator", 0) > 0
            projected_coverage[lane] = {
                **row,
                "disposition": row.get("disposition")
                or ("measured" if measured else "not_applicable"),
                "item_refs": row.get("item_refs", projected_item_refs if measured else []),
                "evidence_refs": row.get(
                    "evidence_refs", projected_evidence_refs if measured else []
                ),
                **(
                    {"reason": row.get("reason") or row.get("conditions") or "not represented"}
                    if not measured
                    else {}
                ),
            }
    else:
        projected_coverage = {
            lane: {
                "numerator": tested if lane == "surface" else 0,
                "denominator": reachable if lane == "surface" else 0,
                "pct": pct if lane == "surface" else 0.0,
                "subject_refs": subject_refs_default,
                "tool": "v3-projection",
                "conditions": (
                    "projected from v3 reachable coverage"
                    if lane == "surface"
                    else "not represented in schema v3"
                ),
                "disposition": (
                    "measured" if lane == "surface" and reachable > 0 else "not_applicable"
                ),
                "item_refs": (
                    projected_item_refs if lane == "surface" and reachable > 0 else []
                ),
                "evidence_refs": (
                    projected_evidence_refs if lane == "surface" and reachable > 0 else []
                ),
                **(
                    {"reason": "not represented in schema v3"}
                    if lane != "surface" or reachable == 0
                    else {}
                ),
            }
            for lane in sorted(COVERAGE_LANES)
        }
    return {
        "schema_version": 4,
        "contract_version": CONTRACT_VERSION,
        "version": document.get("version"),
        "tester_id": document.get("tester_id"),
        "run_id": document.get("run_id"),
        "mode": (
            hybrid.get("mode")
            if hybrid.get("mode") in {"blackbox", "whitebox", "hybrid"}
            else "blackbox"
        ),
        "objective": objective,
        "started_at": document.get("started_at"),
        "finished_at": document.get("finished_at"),
        "subjects": subjects,
        "relations": hybrid.get("relations", []),
        "summary": document.get("summary"),
        "coverage_by_lane": projected_coverage,
        "items": items,
        "gates": [
            {
                "id": gate.get("gate_id"),
                "verdict": gate.get("verdict"),
                "reason": gate.get("reason"),
                "item_ids": gate.get("item_ids", []),
                "evidence_refs": gate.get("evidence_refs", []),
                "required_subject_types": gate.get(
                    "required_subject_types",
                    sorted({subject.get("type", "unknown") for subject in subjects if isinstance(subject, dict)}),
                ),
            }
            for gate in document.get("gate_items", [])
        ],
        "max_claim_scope": hybrid.get("max_claim_scope", "behavior"),
        "missing_capabilities": hybrid.get("missing_capabilities", ["typed-subject-identity"]),
        "input_refs": input_refs,
        "source_impact_ref": (
            hybrid.get("artifacts", {}).get("source_impact")
            if isinstance(hybrid.get("artifacts"), dict)
            else None
        ),
        "compatibility": {
            "projected_from": 3,
            "v3_sha256": sha256_json(document),
        },
        "release_readiness": readiness,
        "provider_metadata": {"legacy_requested_mode": document.get("mode")},
    }


def write_atomic(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text(text, encoding="utf-8")
    os.replace(temporary, path)


def write_atomic_bytes(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_bytes(payload)
    os.replace(temporary, path)
