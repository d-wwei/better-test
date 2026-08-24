#!/usr/bin/env python3
"""Project activated reference-suite cases into compact Agent intent checklists."""

from __future__ import annotations

import argparse
from collections import defaultdict
import json
from pathlib import Path
import subprocess
import sys


def validate(path: Path) -> None:
    subprocess.run(
        [
            sys.executable,
            str(Path(__file__).with_name("validate-reference-suite-map.py")),
            str(path),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
    )


def api_name(file_path: str) -> str:
    return Path(file_path).stem.removeprefix("test_")


def humanize(value: str) -> str:
    return value.replace("_", " ").strip()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("map_file", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--include-status",
        action="append",
        dest="statuses",
        choices=["direct", "adapted", "oracle-only"],
    )
    args = parser.parse_args()
    validate(args.map_file)
    document = json.loads(args.map_file.read_text(encoding="utf-8"))
    statuses = set(args.statuses or ["direct", "adapted"])
    by_file: dict[str, list[dict]] = defaultdict(list)
    for case in document["cases"]:
        if case["adoption_status"] not in statuses:
            continue
        if case["side_effect"] not in {"none", "read"}:
            continue
        by_file[case["file"]].append(case)

    lines = [
        "# Reference Suite Agent Intent Checklist",
        "",
        f"> suite: `{document['suite']['id']}@{document['suite']['commit']}`",
        "> 运行方式：每条意图必须记录成功、失败、blocked 或告警；不能静默跳过。",
        "",
    ]
    for file_path in sorted(by_file):
        cases = by_file[file_path]
        api = api_name(file_path)
        lines.extend([f"## {api}", ""])
        for case in cases:
            target = case["target_test_ids"][0]
            function = humanize(case["function"].removeprefix("test_"))
            lines.extend(
                [
                    f"- [ ] 验证 {humanize(api)}：{function}（`{target}`）",
                    "- [ ] 返回结果符合对应 oracle 和 evidence boundary",
                ]
            )
        lines.append("")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    print(f"generated reference suite intents: {sum(len(v) for v in by_file.values())}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
