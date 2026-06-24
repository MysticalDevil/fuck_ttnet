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

  python3 - "$ROOT_DIR/samples/observed_3011076_drop_rule.json" "$output_path" "$slash_mode" <<'PY'
import json
import sys

sample_path, output_path, slash_mode = sys.argv[1], sys.argv[2], sys.argv[3]
with open(sample_path, "r", encoding="utf-8") as sample_file:
    observed = json.load(sample_file)["data"]["ttnet_dispatch_actions"][0]

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
  case_dir="$WORK_DIR/$slash_mode"

  MODDIR="$case_dir/module"
  FILES_DIR="$case_dir/app/files"
  SERVER_JSON="$FILES_DIR/server.json"
  TT_NET_CONFIG="$FILES_DIR/tt_net_config.config"
  LOG_FILE="$MODDIR/fuck_ttnet.log"
  export MODDIR FILES_DIR SERVER_JSON TT_NET_CONFIG LOG_FILE

  mkdir -p "$MODDIR" "$FILES_DIR"
  build_server_json "$SERVER_JSON" "$slash_mode"
  printf 'prefix dispatch:1,3011076,2 suffix\n' > "$TT_NET_CONFIG"

  # shellcheck disable=SC1091
  . "$ROOT_DIR/common/ttnet_patch.sh"

  patch_tiktok_ttnet

  if grep -q '3011076' "$SERVER_JSON" "$TT_NET_CONFIG"; then
    echo "test: 3011076 was not fully removed for $slash_mode JSON" >&2
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

run_case "plain"
run_case "escaped"

echo "test: patch patterns passed"
