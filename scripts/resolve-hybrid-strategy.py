#!/usr/bin/env python3
"""Resolve testing mode and evidence lanes from objective, capabilities, and impact."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from hybrid_core import (
    OBJECTIVE_MAX_CLAIM,
    OBJECTIVE_REQUIRED_CAPABILITIES,
    derive_claim_ceiling,
    derive_mode,
    dump_json,
    load_json,
    validate,
    validate_capabilities_against_profile,
    write_atomic,
)


OBJECTIVE_POLICY: dict[str, dict[str, Any]] = {
    "source_change": {
        "preferred_mode": "hybrid",
        "required_lanes": ["inventory", "diff", "risk", "selection"],
        "required_capabilities": sorted(OBJECTIVE_REQUIRED_CAPABILITIES["source_change"]),
        "max_claim_scope": OBJECTIVE_MAX_CLAIM["source_change"],
    },
    "package_validation": {
        "preferred_mode": "hybrid",
        "required_lanes": ["surface", "inventory", "risk", "invariant", "selection"],
        "required_capabilities": sorted(OBJECTIVE_REQUIRED_CAPABILITIES["package_validation"]),
        "max_claim_scope": OBJECTIVE_MAX_CLAIM["package_validation"],
    },
    "behavior_regression": {
        "preferred_mode": "hybrid",
        "required_lanes": ["surface", "risk", "invariant", "selection"],
        "required_capabilities": sorted(OBJECTIVE_REQUIRED_CAPABILITIES["behavior_regression"]),
        "max_claim_scope": OBJECTIVE_MAX_CLAIM["behavior_regression"],
    },
    "release_decision": {
        "preferred_mode": "hybrid",
        "required_lanes": ["surface", "inventory", "code", "diff", "risk", "invariant", "selection"],
        "required_capabilities": sorted(OBJECTIVE_REQUIRED_CAPABILITIES["release_decision"]),
        "max_claim_scope": OBJECTIVE_MAX_CLAIM["release_decision"],
    },
    "bug_investigation": {
        "preferred_mode": "hybrid",
        "required_lanes": ["surface", "inventory", "code", "diff", "risk", "invariant", "selection"],
        "required_capabilities": sorted(OBJECTIVE_REQUIRED_CAPABILITIES["bug_investigation"]),
        "max_claim_scope": OBJECTIVE_MAX_CLAIM["bug_investigation"],
        "required_phases": ["reproduce", "localize", "rebuild", "reverify"],
    },
}

# Profiles may use task-language aliases; resolution records both the requested
# objective and its normalized policy so replay stays deterministic.
OBJECTIVE_ALIASES = {
    "code_change_validation": "source_change",
    "knowledge_refresh": "source_change",
    "artifact_acceptance": "package_validation",
    "regression_only": "behavior_regression",
    "exploratory_assessment": "behavior_regression",
}


def available_capabilities(document: dict[str, Any]) -> set[str]:
    return {
        row["name"]
        for row in document.get("capabilities", [])
        if isinstance(row, dict) and row.get("status") == "available" and isinstance(row.get("name"), str)
    }


def stable_unique(values: list[str]) -> list[str]:
    return list(dict.fromkeys(values))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--objective",
        choices=tuple(OBJECTIVE_POLICY) + tuple(OBJECTIVE_ALIASES),
        required=True,
    )
    parser.add_argument("--capabilities", type=Path, required=True)
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--impact", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        capabilities = load_json(args.capabilities)
        profile = load_json(args.profile)
        errors = validate("capabilities", capabilities) + validate("project-profile", profile)
        errors += validate_capabilities_against_profile(capabilities, profile)
        impact = load_json(args.impact) if args.impact else None
        if impact is not None:
            errors += validate("source-impact", impact)
        if errors:
            raise ValueError("; ".join(errors))
    except (OSError, ValueError) as exc:
        print(f"strategy resolution failed: {exc}", file=sys.stderr)
        return 2

    normalized_objective = OBJECTIVE_ALIASES.get(args.objective, args.objective)
    policy = OBJECTIVE_POLICY[normalized_objective]
    available = available_capabilities(capabilities)
    reported = {
        row.get("name")
        for row in capabilities.get("capabilities", [])
        if isinstance(row, dict)
    }
    omitted = set(policy["required_capabilities"]) - reported
    if omitted:
        print(
            "strategy resolution failed: capability probe omits objective-required rows: "
            + ", ".join(sorted(omitted)),
            file=sys.stderr,
        )
        return 2
    features = profile.get("features", {})
    if features.get("results_v4") == "off":
        print("strategy resolution failed: project profile disables results v4", file=sys.stderr)
        return 2
    hybrid_enabled = features.get("hybrid_testing") is True
    effective_available = set(available)
    if not hybrid_enabled:
        effective_available -= {"source-map", "source-impact"}
    missing = sorted(set(policy["required_capabilities"]) - effective_available)
    mode = derive_mode(effective_available, hybrid_enabled)

    required_lanes = list(policy["required_lanes"])
    required_gates: list[str] = []
    reasons = [f"objective={args.objective}", f"capability-derived mode={mode}"]
    confidence = "not_applicable"
    mutation_required_for = profile.get("evidence_policy", {}).get("mutation", {}).get(
        "required_for", []
    )
    matched_mutation_triggers: list[str] = []
    if impact is not None:
        required_lanes.extend(impact.get("required_lanes", []))
        required_gates.extend(impact.get("required_gates", []))
        confidence = impact.get("confidence", {}).get("level", "low")
        if impact.get("unknown_changes") or confidence == "low":
            required_lanes.extend(profile["evidence_policy"]["safe_default_lanes"])
            reasons.append("unknown or low-confidence impact expanded to safe default")
        matched_mutation_triggers = sorted(
            set(impact.get("mutation_triggers", [])) & set(mutation_required_for)
        )
        if matched_mutation_triggers:
            required_lanes.extend(["code", "risk", "selection"])
            required_gates.append("mutation-adequacy")
            reasons.append("profile mutation policy matched source-impact triggers")
    extensions = profile.get("extensions", {})
    if normalized_objective in {"package_validation", "release_decision"} and isinstance(extensions, dict):
        fixed_gates = extensions.get("release_fixed_gates", [])
        if isinstance(fixed_gates, list) and all(isinstance(value, str) for value in fixed_gates):
            required_gates.extend(fixed_gates)
            if fixed_gates:
                reasons.append("project release fixed gates preserved")
    if mode == "blackbox":
        required_lanes = [lane for lane in required_lanes if lane not in {"code", "diff"}]
        required_lanes.extend(["surface", "invariant", "selection"])
        reasons.append("source capabilities unavailable; preserved black-box safety lanes")
    max_claim_scope = derive_claim_ceiling(normalized_objective, effective_available)
    if missing:
        reasons.append("claim scope capped by missing capabilities")

    required_phases = list(policy.get("required_phases", []))
    blocked_phases: list[str] = []
    if normalized_objective == "bug_investigation" and "runtime-probe" in missing:
        blocked_phases = ["reproduce", "reverify"]
        reasons.append("bug investigation cannot close reproduce/reverify without a runtime probe")

    result = {
        "schema_version": 1,
        "objective": args.objective,
        "normalized_objective": normalized_objective,
        "mode": mode,
        "required_lanes": stable_unique(required_lanes),
        "recommended_lanes": [],
        "excluded_lanes": [],
        "required_gates": stable_unique(required_gates),
        "max_claim_scope": max_claim_scope,
        "missing_capabilities": missing,
        "impact_confidence": confidence,
        "reasons": reasons,
        "required_phases": required_phases,
        "blocked_phases": blocked_phases,
        "feature_flags": features,
        "mutation_required_for": mutation_required_for,
        "mutation_required": bool(matched_mutation_triggers),
        "mutation_triggers": matched_mutation_triggers,
    }
    write_atomic(args.output, dump_json(result))
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
