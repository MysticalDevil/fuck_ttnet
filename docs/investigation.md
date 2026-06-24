# TikTok TTNet 3011076 / -555 Investigation

This note documents the evidence behind the module. It separates the confirmed
client-side mechanism from the still-unproven server-side reason TikTok selected
the policy.

## Summary

The observed no-network state was caused locally by a cached TTNet/TNC dispatch
action:

```text
rule_id=3011076
action="tc"
service_name="drop flow"
host_group=["*"]
contain_group=["/"]
drop=1
possibility=100
```

This is a global traffic-control drop. The request is rejected by TTNet URL
dispatch before DNS, TCP connect, or TLS starts. That matches the log signature:

```text
ERR_TTNET_TRAFFIC_CONTROL_DROP
InternalErrorCode=-555
dns=-1, connect=-1, ssl=-1
```

`3011076` is a TTNet/TNC dispatch rule ID. It is not an Android network error,
SIM country code, MCC/MNC value, or proxy code. The ID labels the rule; the rule
body causes the failure.

## Evidence Matrix

Current evidence supports the client-side mechanism, not the server-side rule
selection condition:

| Question | Evidence | Status |
| --- | --- | --- |
| Did the device receive rule `3011076`? | Preserved `server.json.bak_` has one `ttnet_dispatch_actions` entry with `rule_id=3011076`; preserved `tt_net_config.config.bak_` lists `3011076` in dispatch metadata. | Proven for this device state. |
| What does the rule body do? | `action="tc"`, wildcard `host_group`, `contain_group=["/"]`, `drop=1`, `possibility=100`, `service_name="drop flow"`. | Proven from local backup. |
| Does TTNet interpret that body as a local drop? | Current APK smali and public decompiled source both parse `tc`, `drop`, `drop_code`, and `possibility`; matching drop actions set the dispatched URL to empty and return `DISPATCH_DROP`. | Proven for client behavior. |
| Why does logcat show no DNS/connect/TLS timing? | Callers throw `ERR_TTNET_TRAFFIC_CONTROL_DROP` when the dispatch result URL is empty and matched rule IDs are non-empty. | Proven from current APK smali and public source. |
| Why did TikTok select `3011076`? | Public exact-ID searches found no matching source, sample, issue, or rule body. Device-side data shows the cached rule after selection, not the server's decision input. | Not proven. |

## Device Evidence

The failing TikTok data directory contained `3011076` in TTNet local cache:

```text
/data/data/com.zhiliaoapp.musically/files/server.json
/data/data/com.zhiliaoapp.musically/files/tt_net_config.config
```

The bad `server.json` action was a wildcard host/path drop. Logcat showed
`ERR_TTNET_TRAFFIC_CONTROL_DROP` with internal error `-555` and no DNS/connect
or SSL phase. Removing that action changed behavior from local drops to real
network responses such as HTTP 200.

Current clean-state checks showed zero `3011076` hits in active TikTok TTNet
files and shared preferences. The current `tt_net_config.config` still contains
a `dispatch:` summary list, but no `3011076`. That supports treating the number
as a runtime TNC/dispatch rule ID.

Older preserved backups still contain the evidence:

```text
/data/data/com.zhiliaoapp.musically/files/server.json.bak_
/data/data/com.zhiliaoapp.musically/files/tt_net_config.config.bak_
```

Each of those backup files has one `3011076` hit. The `tt_net_config.config`
backup contains `3011076` inside the `dispatch:` rule-ID summary list. The
active files do not.

The preserved `server.json.bak_` was parsed as JSON. It contains exactly one
matching action at:

```text
/data/ttnet_dispatch_actions[136]
```

The extracted action is:

```json
{
  "act_priority": 1083,
  "action": "tc",
  "param": {
    "contain_group": [
      "/"
    ],
    "drop": 1,
    "drop_reason": 2,
    "host_group": [
      "*"
    ],
    "possibility": 100,
    "service_name": "drop flow"
  },
  "rule_id": 3011076,
  "sign": "8fc59003d5651cd6c03a25371b69eb51"
}
```

That observed action is preserved as
`samples/observed_3011076_drop_rule.json`.

The extraction can be repeated without modifying the device:

```sh
adb exec-out su -c \
  'cat /data/data/com.zhiliaoapp.musically/files/server.json.bak_' |
  python3 scripts/extract_ttnet_rule.py --input -
```

## Current APK Smali Evidence

The current TikTok APK was checked with baksmali from the real upstream
project, `JesusFreke/smali` on Bitbucket. The usable artifact was
`baksmali-2.5.2.jar`; the repository tags also show `v2.5.2` as the latest
published tag in that upstream.

Important note: obfuscated class names from older public decompiled source do
not map one-to-one onto this TikTok build. For example, the current APK has
`LX/0zIO`, but that class is not the TTNet dispatcher in this build. The
current APK evidence below is therefore based on strings and bytecode behavior,
not on reusing old obfuscated names.

The current APK's `classes21.dex` contains the TTNet dispatch implementation:

- `Li34/l` parses `request_delay_actions`, `ttnet_url_dispatcher_enabled`,
  `ttnet_dispatch_actions_epoch`, and `ttnet_dispatch_actions`.
- `Li34/l.LJII(JSONObject)` parses per-action `action`, `act_priority`,
  `param`, `rule_id`, `sign`, `request_method`, and `set_req_priority`, then
  constructs a dispatch action.
- `LX/0k7I` is the `tc` action implementation. It parses `service_name`,
  replacement fields, `drop`, `drop_code`, and `possibility`.
- `LX/0k7X` defines the dispatch enum values, including `DISPATCH_DROP`.
- `Li34/e` is the dispatch result object. Its constructor initializes the
  dispatch result URL to an empty-safe string/list state and default drop code
  to `-555`.
- `LX/0k5r` is an OkHttp path using `Li34/l`. If the dispatched URL is empty
  and the matched rule-ID list is non-empty, it throws
  `ERR_TTNET_TRAFFIC_CONTROL_DROP`.
- `LX/0kTg` contains a second GET-style dispatch path with the same empty URL
  plus matched-rule-list traffic-control behavior.
- `com/ss/bduploader/util/BDUrlDispatch` uses the public URLDispatcher
  reflection path and applies the same empty dispatched URL plus matched rule
  list check.

The `tc` drop behavior is explicit in current smali:

1. `LX/0k7I` reads `drop`; if it is `1`, the action is marked as a drop action.
2. It reads `drop_code`. Accepted values are `-555` or the range
   `-5559..-5551`.
3. It reads `possibility`, defaulting to `100`.
4. When a matching drop action passes the probability check, it writes an empty
   string into the mutable dispatched URL slot and returns `DISPATCH_DROP`.
5. `Li34/l` records the matched rule ID and copies the action drop code into
   the dispatch result.
6. The caller sees an empty dispatched URL plus non-empty matched rule IDs and
   raises `ERR_TTNET_TRAFFIC_CONTROL_DROP`.

This is the white-box explanation for why the failing logs show no DNS,
connect, or TLS phase: the request was dropped by local TTNet URL dispatch
before network I/O.

The pulled APK and extracted dex files were also searched for the literal
`3011076`. No hit was found. That supports the current interpretation that
`3011076` is not an APK-bundled constant; it is a runtime rule ID from cached
or server-delivered TNC state.

Important local smali probes from the current APK:

| File | Evidence |
| --- | --- |
| `/tmp/fuck_ttnet_baksmali_current/X/0k7I.smali` | Parses `service_name`, `drop`, `drop_code`, and `possibility`; when a matching drop action passes probability, writes `""` to the dispatched URL slot and returns `DISPATCH_DROP`. |
| `/tmp/fuck_ttnet_baksmali_current/i34/l.smali` | Parses `ttnet_url_dispatcher_enabled`, `ttnet_dispatch_actions_epoch`, `ttnet_dispatch_actions`, `rule_id`, `sign`, and `request_method`; records matched rule IDs and copies the action drop code into the dispatch result. |
| `/tmp/fuck_ttnet_baksmali_current/X/0k5r.smali` | Throws `ERR_TTNET_TRAFFIC_CONTROL_DROP` when dispatch output URL is empty and the matched rule-ID list is non-empty. |
| `/tmp/fuck_ttnet_baksmali_current/X/0kTg.smali` | A second request path throws or handles `ERR_TTNET_TRAFFIC_CONTROL_DROP, -555` with the same empty URL plus matched-rule-list semantics. |
| `/tmp/fuck_ttnet_baksmali_classes21/com/ss/bduploader/util/BDUrlDispatch.smali` | Reflects `mDispatchedURL` and `mActionRuleIdList`; throws `ERR_TTNET_TRAFFIC_CONTROL_DROP, -555` when dispatched URL is empty and the rule list is non-empty. |
| `/tmp/fuck_ttnet_baksmali_classes21/com/bytedance/ttnet/tnc/TNCManager.smali` | Stores TNC state under `ttnet_tnc_config`, confirming that TTNet policy is cached runtime configuration. |

The repository includes a helper to reproduce the local smali probe:

```sh
BAKSMALI_JAR=/tmp/baksmali-2.5.2.jar \
DEX_FILE=/tmp/tiktok_base_dex/classes21.dex \
  scripts/probe_ttnet_smali.sh
```

## Public Source Evidence

Public decompiled TikTok/TTNet source shows the same relevant design, but should
be treated as supporting evidence rather than a class-name map for the current
APK:

1. `SsOkHttp3Client` loads local TNC from shared preferences named
   `ttnet_tnc_config`, key `tnc_config_str`, then passes the JSON into
   `C1894690zIO.LJII(...)`.
2. `C1894690zIO.LJII(...)` parses `ttnet_dispatch_actions` and each action's
   `action`, `act_priority`, `param`, `rule_id`, `sign`, `request_method`, and
   `set_req_priority`.
3. `BaseDispatchAction.LIZ(...)` creates the implementation for `action="tc"`.
   That implementation parses:

```text
host_group
equal_group
prefixes_group
contain_group
pattern_group
url_group
path_contain
service_name
scheme_replace
host_replace
path_replace
replace
drop
drop_code
possibility
```

4. For a matching `tc` rule with `drop=1`, the implementation sets the
   dispatched URL to an empty string and returns `DISPATCH_DROP`.
5. The default drop code is `-555`. A configured `drop_code` is accepted only if
   it is `-555` or in the range `-5559..-5551`.
6. The OkHttp request path checks the dispatch result. If the dispatched URL is
   empty and the matched rule ID list is non-empty, it throws
   `ERR_TTNET_TRAFFIC_CONTROL_DROP` with the drop code.
7. `BDUrlDispatch` contains the same semantic check through the public
   URLDispatcher reflection path: empty dispatched URL plus non-empty
   `mActionRuleIdList` becomes `ERR_TTNET_TRAFFIC_CONTROL_DROP, -555`.

Additional public-source observations:

- Public TikTok decompiled source contains bundled/sample TNC JSON with
  `ttnet_dispatch_actions` and `action="tc"` rules that use `drop=1`,
  `host_group=["*"]`, path patterns, and `possibility=100`. That proves TTNet
  traffic-control drops are a normal TNC policy shape, independent of the
  observed rule ID.
- The same source exposes the client-side parser for `drop_code`, including
  the default `-555` behavior and the accepted custom range `-5559..-5551`.
- Public WebSocket and upload paths reuse the same URL dispatch result shape.
  They do not perform DNS or socket work when URL dispatch has already produced
  a traffic-control drop.

The direct body of `C1894690zIO.LIZ(...)` was not cleanly decompiled in the
public source. However, the parser, action implementation, result object fields,
and multiple callers are enough to establish the client-side drop mechanism.

## What 3011076 Represents

Best current interpretation:

```text
3011076 = TTNet/TNC dispatch action rule ID
```

It is used as rule metadata and for matched-rule reporting. The blocking
behavior is not caused by the numeric value itself. The behavior comes from the
rule body:

```text
action="tc" + host/path match + drop=1 + possibility=100
```

Public source and public TNC samples contain the same dispatch action schema,
but no public source search found a hardcoded `3011076` constant. That is
consistent with the ID being server-delivered runtime policy.

## External Search Notes

Additional public searches were run for exact and schema-level terms:

```text
"3011076" "TTNet"
"3011076" "ttnet_dispatch_actions"
"rule_id":3011076
"ERR_TTNET_TRAFFIC_CONTROL_DROP"
"drop_code" "DISPATCH_DROP" "ttnet"
"mDispatchedURL" "mActionRuleIdList"
```

GitHub code search was also run with scoped queries:

```sh
gh search code '3011076 repo:cxxsheng/TiktokSource' --limit 20
gh search code '3011076 user:EduardoC3677' --limit 20
gh search code 'ERR_TTNET_TRAFFIC_CONTROL_DROP' --limit 20
gh search code 'ttnet_dispatch_actions repo:cxxsheng/TiktokSource' --limit 20
gh search code 'drop_code repo:cxxsheng/TiktokSource' --limit 20
gh search code 'mActionRuleIdList mDispatchedURL repo:cxxsheng/TiktokSource' --limit 20
```

The scoped `3011076` searches returned no hits. The broad exact-ID search timed
out once on GitHub, so the absence of a broad public hit is not a formal proof.
The useful public evidence remains schema-level and client-code evidence:
TTNet/TNC dispatch actions use `rule_id`, `action`, `param`, and `drop`
semantics, while the current APK smali shows how this build applies those
semantics.

The repository includes a repeatable helper for these public searches:

```sh
scripts/search_public_evidence.sh
```

## White-Box Demo

The repository includes a small local model of the relevant TTNet dispatch
logic:

```sh
python3 scripts/ttnet_dispatch_model.py --self-test
python3 scripts/ttnet_dispatch_model.py \
  --config samples/3011076_drop_rule.json \
  --url 'https://api16-normal-c-useast1a.tiktokv.com/aweme/v2/feed/'
python3 scripts/ttnet_dispatch_model.py \
  --config samples/observed_3011076_drop_rule.json \
  --url 'https://api16-normal-c-useast1a.tiktokv.com/aweme/v2/feed/'
```

Expected modeled result:

```json
{
  "drop_code": -555,
  "input_url": "https://api16-normal-c-useast1a.tiktokv.com/aweme/v2/feed/",
  "matched_rule_ids": [
    3011076
  ],
  "output_url": "",
  "result": "DISPATCH_DROP"
}
```

This is not a true reproduction of TikTok selecting `3011076`. It proves the
client-side result once such a rule is present in local TNC config.

The observed backup can also be piped directly into the model:

```sh
adb exec-out su -c \
  'cat /data/data/com.zhiliaoapp.musically/files/server.json.bak_' |
  python3 scripts/extract_ttnet_rule.py --input - --sample |
  python3 scripts/ttnet_dispatch_model.py \
    --config - \
    --url 'https://api16-normal-c-useast1a.tiktokv.com/aweme/v2/feed/'
```

The demo intentionally does not inject `3011076` into TikTok. It models the
white-box dispatch mechanism against either the synthetic sample or the observed
backup. A true server-side reproduction would require observing TikTok fetching
or retaining `3011076` from TNC under controlled account/device/network
conditions, which has not been achieved yet.

## Patch Regression

The module patch pattern is tested against the observed `3011076` rule body:

```sh
scripts/test_patch_patterns.sh
```

This builds temporary TTNet files from `samples/observed_3011076_drop_rule.json`,
invokes the real `common/ttnet_patch.sh` functions, and checks that:

- `3011076` is removed from temporary `server.json`.
- `3011076` is removed from temporary `tt_net_config.config`.
- Neighboring dispatch actions remain valid JSON.
- Both JSON slash forms are covered: `["/"]` and the observed `["\\/"]`.

## Not Proven Yet

The exact server-side selection condition for `3011076` is still not proven.
Possible inputs include account state, store region, carrier/network region,
proxy exit region, device history, and cached policy state. The current evidence
does not justify claiming that the SIM card alone caused the rule.

## Practical Collection Steps

When the failure appears again, collect these before patching:

```sh
scripts/collect_device_evidence.sh
scripts/collect_device_evidence.sh adb-DEVICE-SERIAL /tmp/fuck_ttnet_evidence_case
```

The script is read-only. It records `3011076` hit counts, file sizes, matching
rule actions extracted with `scripts/extract_ttnet_rule.py`, and filtered
logcat. It does not copy the full TTNet config files by default.

Manual equivalents:

```sh
pkg_dir=/data/data/com.zhiliaoapp.musically
adb shell su -c \
  "grep -Rsn 3011076 $pkg_dir/files $pkg_dir/shared_prefs"
adb shell su -c \
  "strings $pkg_dir/files/tt_net_config.config | grep 3011076"
adb logcat -d -v time |
  grep -E 'ERR_TTNET|TRAFFIC_CONTROL|InternalErrorCode=-555|dns=-1|connect=-1|ssl=-1'
```

Also preserve the surrounding `server.json` action if possible. The important
evidence is the rule body, not only the numeric ID.

## References

- smali/baksmali upstream used for current APK bytecode inspection:
  <https://bitbucket.org/JesusFreke/smali>
- Reverse-engineered TikTok Java source used for local code reading:
  <https://github.com/cxxsheng/TiktokSource>
- Public TNC response sample showing the same `ttnet_dispatch_actions` /
  `rule_id` schema: <https://gist.github.com/catscarlet/e94a5b2dbd53b319912fd04e987169d2>
