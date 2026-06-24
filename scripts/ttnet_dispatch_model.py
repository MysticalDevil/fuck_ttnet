#!/usr/bin/env python3
"""Model the TTNet URL dispatch path relevant to traffic-control drops.

Inputs:
  --config CONFIG_JSON  TTNet JSON containing data.ttnet_dispatch_actions.
                        Use "-" to read stdin.
  --url URL             Request URL to dispatch

Expected output:
  JSON with the modeled dispatch result, matched rule IDs, and drop code.

This is a white-box model of the public decompiled TTNet Java logic. It does
not download TikTok server policy and does not modify any Android device file.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import re
import sys
from dataclasses import dataclass
from typing import Any
from urllib.parse import urlparse


DEFAULT_DROP_CODE = -555


@dataclass(frozen=True)
class DispatchResult:
    result: str
    input_url: str
    output_url: str
    matched_rule_ids: list[int]
    drop_code: int

    def to_json(self) -> str:
        return json.dumps(
            {
                "result": self.result,
                "input_url": self.input_url,
                "output_url": self.output_url,
                "matched_rule_ids": self.matched_rule_ids,
                "drop_code": self.drop_code,
            },
            indent=2,
            sort_keys=True,
        )


def _as_list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def _valid_drop_code(value: Any) -> int:
    if isinstance(value, int) and (value == -555 or -5559 <= value <= -5551):
        return value
    return DEFAULT_DROP_CODE


def _host_matches(host: str, patterns: list[Any]) -> bool:
    if not patterns:
        return True
    return any(isinstance(item, str) and fnmatch.fnmatchcase(host, item) for item in patterns)


def _path_matches(path: str, params: dict[str, Any], url: str) -> bool:
    equal_group = _as_list(params.get("equal_group"))
    prefixes_group = _as_list(params.get("prefixes_group"))
    contain_group = _as_list(params.get("contain_group"))
    pattern_group = _as_list(params.get("pattern_group"))
    url_group = _as_list(params.get("url_group"))
    path_contain = _as_list(params.get("path_contain"))

    if any(isinstance(item, str) and path == item for item in equal_group):
        return True
    if any(isinstance(item, str) and path.startswith(item) for item in prefixes_group):
        return True
    if any(isinstance(item, str) and item in path for item in contain_group):
        return True
    if any(isinstance(item, str) and re.search(item, path) for item in pattern_group):
        return True
    if url_group:
        if path_contain and not any(isinstance(item, str) and item in path for item in path_contain):
            return False
        return any(isinstance(item, str) and re.search(item, url) for item in url_group)
    return False


def _matches_tc_rule(action: dict[str, Any], url: str) -> bool:
    params = action.get("param")
    if not isinstance(params, dict):
        return False

    parsed = urlparse(url)
    host = parsed.hostname or ""
    path = parsed.path or ""
    if not host or not path:
        return False

    if not _host_matches(host, _as_list(params.get("host_group"))):
        return False
    return _path_matches(path, params, url)


def dispatch(config: dict[str, Any], url: str) -> DispatchResult:
    data = config.get("data", config)
    actions = _as_list(data.get("ttnet_dispatch_actions")) if isinstance(data, dict) else []
    ordered_actions = sorted(
        (item for item in actions if isinstance(item, dict)),
        key=lambda item: item.get("act_priority", 0),
    )

    matched_rule_ids: list[int] = []
    output_url = url
    drop_code = DEFAULT_DROP_CODE

    for action in ordered_actions:
        if action.get("action") != "tc":
            continue
        if not _matches_tc_rule(action, output_url):
            continue

        rule_id = action.get("rule_id")
        if isinstance(rule_id, int):
            matched_rule_ids.append(rule_id)

        params = action.get("param")
        if not isinstance(params, dict):
            continue
        if params.get("drop") != 1:
            continue

        possibility = params.get("possibility", 100)
        if not isinstance(possibility, int) or possibility < 100:
            continue

        drop_code = _valid_drop_code(params.get("drop_code"))
        return DispatchResult(
            result="DISPATCH_DROP",
            input_url=url,
            output_url="",
            matched_rule_ids=matched_rule_ids,
            drop_code=drop_code,
        )

    return DispatchResult(
        result="DISPATCH_NONE",
        input_url=url,
        output_url=output_url,
        matched_rule_ids=matched_rule_ids,
        drop_code=drop_code,
    )


def _rule(params: dict[str, Any], rule_id: int = 3011076) -> dict[str, Any]:
    return {
        "act_priority": 1,
        "action": "tc",
        "param": params,
        "rule_id": rule_id,
        "sign": str(rule_id),
    }


def self_test() -> None:
    feed_url = "https://api16-normal-c-useast1a.tiktokv.com/aweme/v2/feed/"
    base_params = {
        "contain_group": ["/"],
        "drop": 1,
        "drop_reason": 2,
        "host_group": ["*"],
        "possibility": 100,
        "service_name": "drop flow",
    }

    result = dispatch({"data": {"ttnet_dispatch_actions": [_rule(base_params)]}}, feed_url)
    assert result.result == "DISPATCH_DROP"
    assert result.output_url == ""
    assert result.matched_rule_ids == [3011076]
    assert result.drop_code == DEFAULT_DROP_CODE

    no_match = dispatch(
        {"data": {"ttnet_dispatch_actions": [_rule({**base_params, "contain_group": ["/passport/"]})]}},
        feed_url,
    )
    assert no_match.result == "DISPATCH_NONE"
    assert no_match.output_url == feed_url

    no_probability = dispatch(
        {"data": {"ttnet_dispatch_actions": [_rule({**base_params, "possibility": 0})]}},
        feed_url,
    )
    assert no_probability.result == "DISPATCH_NONE"

    custom_code = dispatch(
        {"data": {"ttnet_dispatch_actions": [_rule({**base_params, "drop_code": -5552})]}},
        feed_url,
    )
    assert custom_code.result == "DISPATCH_DROP"
    assert custom_code.drop_code == -5552


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", help="TTNet JSON file to model")
    parser.add_argument("--url", help="URL to dispatch through the model")
    parser.add_argument("--self-test", action="store_true", help="run built-in regression checks")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.self_test:
        self_test()
        print("self-test passed")
        return 0

    if not args.config or not args.url:
        raise SystemExit("--config and --url are required unless --self-test is used")

    if args.config == "-":
        config = json.load(sys.stdin)
    else:
        with open(args.config, "r", encoding="utf-8") as config_file:
            config = json.load(config_file)
    print(dispatch(config, args.url).to_json())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
