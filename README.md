# Fuck TTNet: TikTok TTNet 3011076 Network Fix

Targeted KernelSU module for TikTok international edition no-network failures
caused by TTNet rule `3011076`, `ERR_TTNET_TRAFFIC_CONTROL_DROP`, and
`InternalErrorCode=-555`.

[中文文档](README.zh-CN.md)

Detailed investigation: [docs/investigation.md](docs/investigation.md)

Search terms: TikTok no network, TikTok TTNet 3011076, TTNet traffic control
drop, `ERR_TTNET_TRAFFIC_CONTROL_DROP`, `InternalErrorCode=-555`,
`DISPATCH_DROP`, `com.zhiliaoapp.musically`.

## Module Purpose

Fuck TTNet removes a cached TTNet traffic-control rule that makes TikTok drop
requests locally before DNS, TCP, or TLS starts.

Target package:

```text
com.zhiliaoapp.musically
```

Target files:

```text
/data/data/com.zhiliaoapp.musically/files/server.json
/data/data/com.zhiliaoapp.musically/files/tt_net_config.config
```

Target rule:

```text
rule_id=3011076
service_name="drop flow"
host_group=["*"]
contain_group=["/"]
drop=1
possibility=100
```

In plain terms: all hosts, all paths, dropped 100% of the time.

This is the specific `3011076` / `-555` TikTok TTNet failure where logcat shows
local traffic-control drops before DNS, connect, or SSL timing is recorded.

This module does not spoof SIM, device model, locale, timezone, store region,
account region, or proxy settings. It does not clear TikTok data. It only
removes the known local TTNet drop rule and restores TikTok file owner, mode
`0600`, and SELinux context after patching.

Before replacing a file, the module creates a one-time backup next to it with
the suffix `.fuck_ttnet.bak`.

## Module Usage

Build a module zip from this repo:

```sh
scripts/package.sh
```

Install the module zip in KernelSU Manager and reboot.

After boot, force-stop and reopen TikTok:

```sh
adb shell am force-stop com.zhiliaoapp.musically
```

If the manager supports module actions, run the action manually to patch and
print status. It reports rule hit counts before and after patching.

Disable or uninstall the module from KernelSU Manager when it is no longer
needed.

## Manual Fix

The module does not hook TikTok or spoof the device. Its logic is intentionally
small:

1. Wait until TikTok data exists.
2. Back up the target files once with the `.fuck_ttnet.bak` suffix.
3. Remove the exact global `3011076` drop action from `server.json`.
4. Remove `3011076` from the dispatch rule-ID list in `tt_net_config.config`.
5. Restore TikTok file owner, mode `0600`, and SELinux context.

If you do not want to install the module, you can apply the same fix manually
with root. First force-stop TikTok and back up the files:

```sh
adb shell am force-stop com.zhiliaoapp.musically
adb shell su -c 'cd /data/data/com.zhiliaoapp.musically/files &&
  cp server.json server.json.manual.bak 2>/dev/null;
  cp tt_net_config.config tt_net_config.config.manual.bak 2>/dev/null'
```

Then remove only the known bad rule:

- In `server.json`, delete the complete JSON object whose `rule_id` is
  `3011076` and whose body contains `action="tc"`, `service_name="drop flow"`,
  `host_group=["*"]`, `contain_group=["/"]`, `drop=1`, and
  `possibility=100`.
- In `tt_net_config.config`, remove `3011076` from the cached `dispatch:` rule
  list if it is present.

After editing, fix ownership/context and restart TikTok:

```sh
adb shell su -c 'ls -ldn /data/data/com.zhiliaoapp.musically/files'
```

Use the numeric owner/group shown by `ls -ldn` for `APP_UID:APP_GID` below:

```sh
adb shell su -c 'cd /data/data/com.zhiliaoapp.musically/files &&
  chown APP_UID:APP_GID server.json tt_net_config.config 2>/dev/null;
  chmod 600 server.json tt_net_config.config 2>/dev/null;
  restorecon server.json tt_net_config.config 2>/dev/null'
adb shell am force-stop com.zhiliaoapp.musically
```

Do not delete unrelated TTNet rules. Do not publish full TTNet config files
without removing private account, token, cookie, or device identifiers.

Module log:

```text
/data/adb/modules/fuck_ttnet/fuck_ttnet.log
```

Useful checks:

```sh
adb shell su -c 'grep -Rsn 3011076 /data/data/com.zhiliaoapp.musically/files'
adb logcat -d -v time |
  grep -E 'ERR_TTNET|TRAFFIC_CONTROL|InternalErrorCode=-555|http code=200'
```

Use this module only when TikTok shows no network while the device network
works and logcat contains the TTNet local-drop signature:

```text
ERR_TTNET_TRAFFIC_CONTROL_DROP
InternalErrorCode=-555
dns=-1, connect=-1, ssl=-1
```

If the error is DNS failure, TLS failure, proxy failure, Android network policy,
or an HTTP response from TikTok servers, this module is not the right fix.

## Why It Happens

TTNet is TikTok's in-app network stack. It loads runtime TNC configuration from
local cache and applies URL dispatch actions before a request reaches the
normal network path.

Normal request path:

```text
TikTok -> DNS -> TCP connect -> TLS -> HTTP request
```

This failure:

```text
TikTok -> TTNet URL dispatch -> local drop (3011076) -> -555
```

That is why the failing logs show `dns=-1`, `connect=-1`, and `ssl=-1`: the
request never leaves TikTok.

**Trigger**: TikTok's TNC service issues or retains rule `3011076` based on
server-side region detection. When TikTok traffic exits through a Hong Kong
proxy node, TikTok's servers see `carrier_region=HK` (or
`carrier_region_v2=454`) and may deliver this global drop rule. MCC/MNC
and SIM region mismatches with the proxy exit region appear to contribute to
the trigger — `mcc_mnc=46011` (China Mobile) combined with a Hong Kong
proxy exit has been observed to reproduce this.

Public decompiled TTNet code matches the observed behavior:

- Local TNC is loaded from `ttnet_tnc_config` / `server.json`.
- `ttnet_dispatch_actions` is parsed into ordered dispatch actions.
- `action="tc"` parses `host_group`, `contain_group`, `drop`, `drop_code`,
  `possibility`, and `service_name`.
- A matching `tc` action with `drop=1` returns `DISPATCH_DROP`.
- The OkHttp path turns an empty dispatched URL plus matched rule IDs into
  `ERR_TTNET_TRAFFIC_CONTROL_DROP`, defaulting to `-555`.

`3011076` is best understood as a TTNet/TNC dispatch rule ID. It is not an
Android error code, SIM/MCC code, or proxy code. The ID labels the server-side
dispatch policy; the actual blocking behavior comes from the rule body
(`drop=1`, wildcard host, path contains `/`, probability 100).

What is proven:

- The device had a cached global drop action with `rule_id=3011076`.
- Removing that action changed TikTok from local `-555` drops to real network
  responses.
- A white-box model of the decompiled TTNet dispatch logic produces the same
  `DISPATCH_DROP`, empty output URL, matched rule ID, and `-555` result for
  the observed rule body.
- TikTok traffic routed through a Hong Kong proxy exit node can trigger the
  server-side TNC service to issue or retain rule `3011076`. This is confirmed
  by observing `carrier_region=HK` / `carrier_region_v2=454` in request
  parameters along with `mcc_mnc=46011` (China Mobile SIM), and the rule
  appearing in local TTNet cache after proxy use.

What is not proven:

- Whether other proxy exit regions or SIM/carrier combinations can also
  trigger `3011076`.
- Whether the deciding signal is solely the proxy exit region, or a combination
  of SIM MCC/MNC mismatch, account region, store region, or device history.
- Scoped public code searches found TTNet traffic-control code and TNC samples,
  but no public hit for the exact `3011076` rule.

## White-Box Mechanism Check

The repository includes a local-only model of the relevant TTNet dispatch
logic:

```sh
python3 scripts/ttnet_dispatch_model.py --self-test
python3 scripts/ttnet_dispatch_model.py \
  --config samples/3011076_drop_rule.json \
  --url 'https://api16-normal-c-useast1a.tiktokv.com/aweme/v2/feed/'
python3 scripts/extract_ttnet_rule.py \
  --input samples/observed_3011076_drop_rule.json --sample |
  python3 scripts/ttnet_dispatch_model.py \
    --config - \
    --url 'https://api16-normal-c-useast1a.tiktokv.com/aweme/v2/feed/'
```

This is not a full reproduction of TikTok selecting rule `3011076`. It only
validates the client-side mechanism after such a rule exists in local TNC
config.

To repeat the public-source search used by the investigation:

```sh
scripts/search_public_evidence.sh
```

## Scope And Limits

- Only TikTok international edition is targeted.
- Only the known `3011076` global drop flow is removed.
- TikTok may rewrite TTNet config after launch, so the service script checks
  repeatedly in the background.
- If TikTok changes the rule ID or config format, the matcher may need an
  update.
- If a request reaches TikTok servers and the server rejects it, this module
  cannot bypass that response.
