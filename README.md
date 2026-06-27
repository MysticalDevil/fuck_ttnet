# Fuck TTNet: TikTok No-Network Diagnostics and Local TTNet Repair

KernelSU module for diagnosing multiple TikTok international edition
no-network classes, with strong local repair support for cached TTNet rule
`3011076` / `ERR_TTNET_TRAFFIC_CONTROL_DROP` / `InternalErrorCode=-555`.

[中文文档](README.zh-CN.md)

Detailed investigation: [docs/investigation.md](docs/investigation.md)

Broader no-network case map: [docs/no-network-cases.md](docs/no-network-cases.md)

Search terms: TikTok no network, TikTok TTNet 3011076, TTNet traffic control
drop, `ERR_TTNET_TRAFFIC_CONTROL_DROP`, `InternalErrorCode=-555`,
`DISPATCH_DROP`, `com.zhiliaoapp.musically`.

Important: this repository now treats diagnosis as the primary job. Current
local repair coverage is:

- strong support: cached local TTNet dispatch drop (`3011076`, `-555`)
- limited support: volatile runtime cache reset for transport failures such as
  `ERR_CERT_AUTHORITY_INVALID` / `-202`
- no local fix: device network validation failures, region unavailability, or
  server-side region policy

See the broader case map above before assuming every failure is `3011076`.

## Current Usability

Current project status:

- reliable enough for the repository's main goal: diagnosing and repairing the
  local cached `3011076` / `-555` TTNet drop
- useful but limited for adjacent cases such as `ERR_CERT_AUTHORITY_INVALID` /
  `-202`, default-network validation failures, and generic UI-only no-network
  states
- not yet a complete general TikTok no-network platform for every regional,
  server-side, SIM-side, or proxy-side failure

In practical terms: this module is already usable as a diagnosis-first KernelSU
tool, but its strongest and most defensible local repair is still the cached
`3011076` dispatch-drop case.

## Module Purpose

Fuck TTNet is a diagnosis-first module. It tells you whether the current
TikTok "no network" state looks like:

- a local TTNet drop that the module can repair
- a TLS/proxy trust failure that the module can only reset around
- a device or server-side issue that needs work outside the module

Its strongest supported repair is still the cached TTNet traffic-control rule
that makes TikTok drop requests locally before DNS, TCP, or TLS starts.

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

WebUI frontend source now lives under `frontend/` and is built with Vite 8 +
TypeScript. The generated static files are written to `webroot/`, and
`scripts/package.sh` runs `pnpm build` automatically before packing.

Install the module zip in KernelSU Manager and reboot.

After boot, force-stop and reopen TikTok:

```sh
adb shell am force-stop com.zhiliaoapp.musically
```

Open the module WebUI from KernelSU Manager. That is now the primary entry
point. It shows:

- diagnosis ID and transport stage
- whether Android currently sees the default network as validated
- local TTNet rule hits and cached metadata
- recent `-555`, `-202`, and generic UI no-network signals
- module logs and region signals observed in TikTok logs

WebUI actions:

- `Refresh`: read the current TTNet state.
- `Attempt Repair`: run the diagnosis-specific local action.
- `Force Stop TikTok`: restart TikTok's in-memory TTNet state after patching.
- `Copy Diagnostics`: copy a redacted status report.

Recent behavior changes in `v1.1.2`:

- copied diagnostics now redact obvious sensitive values such as `device_id`,
  `iid`, and `sessionid`
- WebUI actions are serialized so repeated refresh, repair, and force-stop
  operations do not race each other
- WebUI refresh no longer overwrites the most recent repair output
- host-side `scripts/diagnose_no_network.sh` no longer clears the device's
  entire logcat buffer before collecting a trace
- `device_network_unvalidated` now prefers the active default network state
  over a weaker broad `VALIDATED` grep

Current repair actions:

- `patch_local_ttnet`: remove cached `3011076` metadata and stop TikTok
- `reset_runtime_cache`: clear volatile runtime cache and stop TikTok
- `none`: no supported local repair for the current diagnosis

The intended workflow is through WebUI only; the module no longer exposes a
separate KernelSU action entrypoint.

Disable or uninstall the module from KernelSU Manager when it is no longer
needed.

## Local Repair Logic

The module does not hook TikTok or spoof the device. The repair logic is kept
small and explicit:

1. Wait until TikTok data exists.
2. Back up the target files once with the `.fuck_ttnet.bak` suffix.
3. Remove the exact global `3011076` drop action from `server.json`.
4. Remove `3011076` from the dispatch rule-ID list in `tt_net_config.config`.
5. Restore TikTok file owner, mode `0600`, and SELinux context.

For the supported `3011076` case, you can apply the same fix manually with
root. First force-stop TikTok and back up the files:

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

Use the local TTNet repair only when TikTok shows no network while the device
network works and logcat contains the TTNet local-drop signature:

```text
ERR_TTNET_TRAFFIC_CONTROL_DROP
InternalErrorCode=-555
dns=-1, connect=-1, ssl=-1
```

If the error is device-network validation failure, TLS failure, proxy failure,
Android network policy, or an HTTP response from TikTok servers, the `3011076`
repair is not the right fix.

## Why The 3011076 Repair Exists

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

What is still uncertain is the upstream trigger that makes TikTok issue or
retain `3011076`. Earlier debugging treated Hong Kong proxy exit and
SIM-region mismatch as a likely cause, but the later evidence base is mixed and
that explanation is not strong enough to present as a rule. A safer statement
is:

- `3011076` is a server-delivered TTNet/TNC dispatch rule ID
- once that rule is cached locally, TTNet can enforce it offline as a local
  `-555` drop
- the module only repairs that local cached symptom

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
- The exact upstream decision path that leads to `3011076` is still unresolved.
- Hong Kong region behavior, server-side region policy, proxy exit, SIM
  signals, and device history may all matter, but the repository should not
  present any one of them as the settled trigger without stronger evidence.

What is not proven:

- Whether other proxy exit regions or SIM/carrier combinations can also
  trigger `3011076`.
- Whether the deciding signal is solely the proxy exit region, or a combination
  of SIM MCC/MNC mismatch, account region, store region, or device history.
- Scoped public code searches found TTNet traffic-control code and TNC samples,
  but no public hit for the exact `3011076` rule.

One more class is now proven locally on the same device and should not be
confused with `3011076`: `net::ERR_CERT_AUTHORITY_INVALID` with
`InternalErrorCode=-202`. In that case TTNet/Cronet reaches the TLS stage and
rejects the certificate chain; this module does not fix it. See
[docs/no-network-cases.md](docs/no-network-cases.md).

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
- The strongest supported repair is still the known `3011076` global drop flow.
- The module now runs in passive mode; diagnosis and repair are driven from
  WebUI instead of background auto-patching.
- If TikTok changes the rule ID or config format, the matcher may need an
  update.
- If a request reaches TikTok servers and the server rejects it, this module
  cannot bypass that response.
