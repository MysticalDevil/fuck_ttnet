#!/usr/bin/env sh

# Offline regression test for module TTNet patch patterns.
#
# The test builds temporary TTNet files from the observed 3011076 sample,
# invokes common/ttnet_patch.sh directly, and verifies that the rule is removed
# while surrounding dispatch actions remain parseable.

set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fuck_ttnet_patch_test.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT HUP INT TERM

build_server_json() {
  output_path="$1"
  slash_mode="$2"
  order_mode="$3"

  python3 - "$ROOT_DIR/samples/observed_3011076_drop_rule.json" "$output_path" "$slash_mode" "$order_mode" <<'PY'
import json
import sys

sample_path, output_path, slash_mode, order_mode = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(sample_path, "r", encoding="utf-8") as sample_file:
    observed = json.load(sample_file)["data"]["ttnet_dispatch_actions"][0]

if order_mode == "reordered":
    observed = {
        "param": {
            "drop": 1,
            "drop_reason": 2,
            "host_group": ["*"],
            "possibility": 100,
            "service_name": "drop flow",
            "contain_group": ["/"],
        },
        "rule_id": 3011076,
        "sign": "8fc59003d5651cd6c03a25371b69eb51",
        "act_priority": 1083,
        "action": "tc",
    }

document = {
    "data": {
        "ttnet_dispatch_actions": [
            {
                "act_priority": 1,
                "action": "dispatch",
                "param": {"host_group": ["example.com"]},
                "rule_id": 1,
                "sign": "1",
            },
            observed,
            {
                "act_priority": 2000,
                "action": "tc",
                "param": {
                    "contain_group": ["/health"],
                    "host_group": ["api.example.com"],
                },
                "rule_id": 2,
                "sign": "2",
            },
        ],
        "ttnet_dispatch_actions_epoch": 1,
        "ttnet_url_dispatcher_enabled": 1,
    }
}

with open(output_path, "w", encoding="utf-8") as output_file:
    text = json.dumps(document, separators=(",", ":"), sort_keys=False)
    if slash_mode == "escaped":
        text = text.replace('"/"', '"\\/"')
    output_file.write(text)
PY
}

run_case() {
  slash_mode="$1"
  order_mode="$2"
  case_dir="$WORK_DIR/$slash_mode-$order_mode"

  MODDIR="$case_dir/module"
  FILES_DIR="$case_dir/app/files"
  SERVER_JSON="$FILES_DIR/server.json"
  TT_NET_CONFIG="$FILES_DIR/tt_net_config.config"
  LOG_FILE="$MODDIR/fuck_ttnet.log"
  REMOVE_GLOBAL_DROP_AWK="$ROOT_DIR/common/remove_global_drop.awk"
  export MODDIR FILES_DIR SERVER_JSON TT_NET_CONFIG LOG_FILE REMOVE_GLOBAL_DROP_AWK

  mkdir -p "$MODDIR" "$FILES_DIR"
  build_server_json "$SERVER_JSON" "$slash_mode" "$order_mode"
  printf 'prefix dispatch:1,3011076,2 suffix\n' > "$TT_NET_CONFIG"

  # shellcheck disable=SC1091
  . "$ROOT_DIR/common/ttnet_patch.sh"

  patch_tiktok_ttnet

  if grep -q '3011076' "$SERVER_JSON" "$TT_NET_CONFIG"; then
    echo "test: 3011076 was not fully removed for $slash_mode/$order_mode JSON" >&2
    exit 1
  fi

  python3 - "$SERVER_JSON" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as input_file:
    data = json.load(input_file)
actions = data["data"]["ttnet_dispatch_actions"]
rule_ids = [item.get("rule_id") for item in actions]
assert rule_ids == [1, 2], rule_ids
PY
}

run_case "plain" "observed"
run_case "escaped" "observed"
run_case "plain" "reordered"
run_case "escaped" "reordered"

echo "test: patch patterns passed"
