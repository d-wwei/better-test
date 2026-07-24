#!/usr/bin/env python3
"""Validate Better Test pairwise and equivalence-class plans."""

from __future__ import annotations

import argparse
import itertools
import json
import sys
from pathlib import Path
from typing import Any


def non_empty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def duplicate_values(values: list[Any]) -> list[Any]:
    seen: set[Any] = set()
    duplicates: list[Any] = []
    for value in values:
        try:
            already_seen = value in seen
        except TypeError:
            continue
        if already_seen and value not in duplicates:
            duplicates.append(value)
        else:
            seen.add(value)
    return duplicates


def validate_document(document: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(document, dict):
        return ["document: expected a JSON object"]

    factors_raw = document.get("factors")
    cases_raw = document.get("cases")
    classes_raw = document.get("required_equivalence_classes")
    canaries_raw = document.get("high_risk_canaries")

    for field, value in (
        ("factors", factors_raw),
        ("cases", cases_raw),
        ("required_equivalence_classes", classes_raw),
        ("high_risk_canaries", canaries_raw),
    ):
        if not isinstance(value, list):
            errors.append(f"{field}: expected an array")

    if errors:
        return errors

    assert isinstance(factors_raw, list)
    assert isinstance(cases_raw, list)
    assert isinstance(classes_raw, list)
    assert isinstance(canaries_raw, list)
    if len(factors_raw) < 2:
        errors.append("factors: expected at least two factors for pairwise coverage")
    if not cases_raw:
        errors.append("cases: expected at least one case")
    if not classes_raw:
        errors.append(
            "required_equivalence_classes: expected at least one explicit class"
        )

    factor_levels: dict[str, list[str]] = {}
    factor_names: list[str] = []
    for index, factor in enumerate(factors_raw):
        path = f"factors[{index}]"
        if not isinstance(factor, dict):
            errors.append(f"{path}: expected an object")
            continue
        name = factor.get("name")
        levels = factor.get("levels")
        if not non_empty_string(name):
            errors.append(f"{path}.name: expected a non-empty string")
            continue
        name = name.strip()
        factor_names.append(name)
        if not isinstance(levels, list) or not levels:
            errors.append(f"{path}.levels: expected a non-empty array")
            continue
        invalid_levels = [
            level for level in levels if not non_empty_string(level)
        ]
        if invalid_levels:
            errors.append(f"{path}.levels: every level must be a non-empty string")
            continue
        normalized_levels = [level.strip() for level in levels]
        duplicates = duplicate_values(normalized_levels)
        if duplicates:
            errors.append(
                f"{path}.levels: duplicate level(s): "
                + ", ".join(repr(value) for value in duplicates)
            )
        factor_levels[name] = normalized_levels

    duplicate_factors = duplicate_values(factor_names)
    if duplicate_factors:
        errors.append(
            "factors: duplicate factor name(s): "
            + ", ".join(repr(value) for value in duplicate_factors)
        )

    class_definitions: dict[str, dict[str, Any]] = {}
    class_ids: list[str] = []
    for index, class_definition in enumerate(classes_raw):
        path = f"required_equivalence_classes[{index}]"
        if not isinstance(class_definition, dict):
            errors.append(f"{path}: expected an object")
            continue
        class_id = class_definition.get("id")
        factor = class_definition.get("factor")
        levels = class_definition.get("levels")
        predicate = class_definition.get("predicate")
        if not non_empty_string(class_id):
            errors.append(f"{path}.id: expected a non-empty string")
            continue
        class_id = class_id.strip()
        class_ids.append(class_id)
        if not non_empty_string(factor):
            errors.append(f"{path}.factor: expected a non-empty string")
            continue
        factor = factor.strip()
        if factor not in factor_levels:
            errors.append(f"{path}.factor: unknown factor {factor!r}")

        has_levels = isinstance(levels, list) and bool(levels)
        has_predicate = non_empty_string(predicate)
        if has_levels == has_predicate:
            errors.append(
                f"{path}: define exactly one of non-empty levels or predicate"
            )
            continue

        normalized_class = {"factor": factor, "levels": None}
        if has_levels:
            assert isinstance(levels, list)
            if any(not non_empty_string(level) for level in levels):
                errors.append(
                    f"{path}.levels: every level must be a non-empty string"
                )
                continue
            normalized_levels = [level.strip() for level in levels]
            duplicates = duplicate_values(normalized_levels)
            if duplicates:
                errors.append(
                    f"{path}.levels: duplicate level(s): "
                    + ", ".join(repr(value) for value in duplicates)
                )
            if factor in factor_levels:
                unknown_levels = sorted(
                    set(normalized_levels) - set(factor_levels[factor])
                )
                if unknown_levels:
                    errors.append(
                        f"{path}.levels: unknown level(s) for {factor!r}: "
                        + ", ".join(repr(value) for value in unknown_levels)
                    )
            normalized_class["levels"] = normalized_levels
        class_definitions[class_id] = normalized_class

    duplicate_classes = duplicate_values(class_ids)
    if duplicate_classes:
        errors.append(
            "required_equivalence_classes: duplicate id(s): "
            + ", ".join(repr(value) for value in duplicate_classes)
        )

    case_ids: list[str] = []
    normalized_cases: list[tuple[str, dict[str, str], list[str]]] = []
    referenced_classes: set[str] = set()
    expected_factors = set(factor_levels)
    for index, case in enumerate(cases_raw):
        path = f"cases[{index}]"
        if not isinstance(case, dict):
            errors.append(f"{path}: expected an object")
            continue
        case_id = case.get("id")
        values = case.get("values")
        classes = case.get("classes")
        if not non_empty_string(case_id):
            errors.append(f"{path}.id: expected a non-empty string")
            continue
        case_id = case_id.strip()
        case_ids.append(case_id)
        if not isinstance(values, dict):
            errors.append(f"{path}.values: expected an object")
            continue
        actual_factors = set(values)
        missing_factors = sorted(expected_factors - actual_factors)
        unknown_factors = sorted(actual_factors - expected_factors)
        if missing_factors:
            errors.append(
                f"{path}.values: missing factor(s): "
                + ", ".join(repr(value) for value in missing_factors)
            )
        if unknown_factors:
            errors.append(
                f"{path}.values: unknown factor(s): "
                + ", ".join(repr(value) for value in unknown_factors)
            )

        normalized_values: dict[str, str] = {}
        for factor in expected_factors:
            value = values.get(factor)
            if not non_empty_string(value):
                errors.append(
                    f"{path}.values.{factor}: expected a non-empty string"
                )
                continue
            value = value.strip()
            normalized_values[factor] = value
            if value not in factor_levels[factor]:
                errors.append(
                    f"{path}.values.{factor}: illegal level {value!r}"
                )

        if not isinstance(classes, list):
            errors.append(f"{path}.classes: expected an array")
            continue
        if any(not non_empty_string(class_id) for class_id in classes):
            errors.append(
                f"{path}.classes: every class id must be a non-empty string"
            )
            continue
        normalized_class_ids = [class_id.strip() for class_id in classes]
        duplicates = duplicate_values(normalized_class_ids)
        if duplicates:
            errors.append(
                f"{path}.classes: duplicate class id(s): "
                + ", ".join(repr(value) for value in duplicates)
            )
        for class_id in normalized_class_ids:
            if class_id not in class_definitions:
                errors.append(f"{path}.classes: unknown class {class_id!r}")
                continue
            referenced_classes.add(class_id)
            class_definition = class_definitions[class_id]
            allowed_levels = class_definition.get("levels")
            factor = class_definition["factor"]
            if (
                allowed_levels is not None
                and factor in normalized_values
                and normalized_values[factor] not in allowed_levels
            ):
                errors.append(
                    f"{path}.classes: {class_id!r} does not match "
                    f"{factor}={normalized_values[factor]!r}"
                )
        normalized_cases.append(
            (case_id, normalized_values, normalized_class_ids)
        )

    duplicate_cases = duplicate_values(case_ids)
    if duplicate_cases:
        errors.append(
            "cases: duplicate id(s): "
            + ", ".join(repr(value) for value in duplicate_cases)
        )

    missing_classes = sorted(set(class_definitions) - referenced_classes)
    if missing_classes:
        errors.append(
            "required_equivalence_classes: unreferenced class(es): "
            + ", ".join(repr(value) for value in missing_classes)
        )

    covered_pairs: set[tuple[str, str, str, str]] = set()
    for _, values, _ in normalized_cases:
        if set(values) != expected_factors:
            continue
        for left, right in itertools.combinations(factor_names, 2):
            covered_pairs.add((left, values[left], right, values[right]))

    missing_pairs: list[tuple[str, str, str, str]] = []
    for left, right in itertools.combinations(factor_names, 2):
        if left not in factor_levels or right not in factor_levels:
            continue
        for left_value, right_value in itertools.product(
            factor_levels[left], factor_levels[right]
        ):
            pair = (left, left_value, right, right_value)
            if pair not in covered_pairs:
                missing_pairs.append(pair)
    for left, left_value, right, right_value in missing_pairs:
        errors.append(
            "pairwise: missing pair "
            f"{left}={left_value!r} × {right}={right_value!r}"
        )

    known_case_ids = set(case_ids)
    canary_ids: list[str] = []
    for index, canary in enumerate(canaries_raw):
        path = f"high_risk_canaries[{index}]"
        if not isinstance(canary, dict):
            errors.append(f"{path}: expected an object")
            continue
        canary_id = canary.get("id")
        case_id = canary.get("case_id")
        if not non_empty_string(canary_id):
            errors.append(f"{path}.id: expected a non-empty string")
        else:
            canary_ids.append(canary_id.strip())
        if not non_empty_string(case_id):
            errors.append(f"{path}.case_id: expected a non-empty string")
        elif case_id.strip() not in known_case_ids:
            errors.append(
                f"{path}.case_id: unknown case {case_id.strip()!r}"
            )

    duplicate_canaries = duplicate_values(canary_ids)
    if duplicate_canaries:
        errors.append(
            "high_risk_canaries: duplicate id(s): "
            + ", ".join(repr(value) for value in duplicate_canaries)
        )

    return errors


def load_document(path: Path) -> Any:
    def reject_constant(value: str) -> None:
        raise ValueError(f"non-standard JSON constant: {value}")

    def reject_duplicate_keys(
        pairs: list[tuple[str, Any]],
    ) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON key: {key}")
            result[key] = value
        return result

    try:
        with path.open(encoding="utf-8") as handle:
            return json.load(
                handle,
                parse_constant=reject_constant,
                object_pairs_hook=reject_duplicate_keys,
            )
    except OSError as error:
        raise ValueError(f"cannot read {path}: {error}") from error
    except json.JSONDecodeError as error:
        raise ValueError(
            f"invalid JSON at line {error.lineno}, column {error.colno}: "
            f"{error.msg}"
        ) from error


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Validate pairwise coverage, required equivalence classes, "
            "and high-risk canary references."
        )
    )
    parser.add_argument("plan", type=Path, help="pairwise plan JSON file")
    arguments = parser.parse_args()

    try:
        document = load_document(arguments.plan)
    except ValueError as error:
        print(f"pairwise validation failed: {error}", file=sys.stderr)
        return 1

    errors = validate_document(document)
    if errors:
        print(
            f"pairwise validation failed ({len(errors)} error(s)):",
            file=sys.stderr,
        )
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(f"pairwise validation passed: {arguments.plan}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
