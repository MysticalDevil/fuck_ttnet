#!/usr/bin/env python3
"""Extract TTNet/TNC dispatch actions by rule_id.

Inputs:
  --input FILE     TTNet JSON file. Use "-" or omit to read stdin.
  --rule-id ID     Rule ID to extract, default 3011076.
  --sample         Output a minimal TTNet config containing matched actions.

Expected output:
  JSON with matched paths/actions, or a minimal data.ttnet_dispatch_actions
  config suitable for scripts/ttnet_dispatch_model.py when --sample is used.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from json import JSONDecodeError
from typing import Any, TextIO


DEFAULT_RULE_ID = 3011076


@dataclass(frozen=True)
class Match:
    path: str
    action: dict[str, Any]


def _read_json(input_path: str | None) -> Any:
    if not input_path or input_path == "-":
        return json.load(sys.stdin)
    with open(input_path, "r", encoding="utf-8") as input_file:
        return json.load(input_file)


def _walk_rules(value: Any, rule_id: int, path: str = "") -> list[Match]:
    matches: list[Match] = []
    if isinstance(value, dict):
        if value.get("rule_id") == rule_id:
            matches.append(Match(path=path or "/", action=value))
        for key, child in value.items():
            matches.extend(_walk_rules(child, rule_id, f"{path}/{key}"))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            matches.extend(_walk_rules(child, rule_id, f"{path}[{index}]"))
    return matches


def _emit_matches(matches: list[Match], output: TextIO) -> None:
    json.dump(
        {
            "count": len(matches),
            "matches": [
                {
                    "path": match.path,
                    "action": match.action,
                }
                for match in matches
            ],
        },
        output,
        ensure_ascii=False,
        indent=2,
        sort_keys=True,
    )
    output.write("\n")


def _emit_sample(matches: list[Match], output: TextIO) -> None:
    json.dump(
        {
            "data": {
                "ttnet_dispatch_actions": [match.action for match in matches],
                "ttnet_dispatch_actions_epoch": 1,
                "ttnet_url_dispatcher_enabled": 1,
            }
        },
        output,
        ensure_ascii=False,
        indent=2,
        sort_keys=True,
    )
    output.write("\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", help='TTNet JSON file, or "-" for stdin')
    parser.add_argument("--rule-id", type=int, default=DEFAULT_RULE_ID)
    parser.add_argument(
        "--sample",
        action="store_true",
        help="emit a minimal TTNet config containing matched actions",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        root = _read_json(args.input)
    except JSONDecodeError as error:
        print(f"extract: invalid JSON input: {error}", file=sys.stderr)
        return 2

    matches = _walk_rules(root, args.rule_id)

    if args.sample:
        _emit_sample(matches, sys.stdout)
    else:
        _emit_matches(matches, sys.stdout)
    return 0 if matches else 1


if __name__ == "__main__":
    raise SystemExit(main())
