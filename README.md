# Fuck TTNet

Targeted KernelSU module for TikTok's local TTNet traffic-control cache.

[中文文档](README.zh-CN.md)

This module is intentionally narrow. It does not spoof the device, proxy
traffic, clear TikTok data, or change SIM/locale/timezone settings. It only
removes one verified local TTNet rule that makes TikTok drop every request
before the request reaches DNS or the network stack.

## When To Use

Use this module when TikTok international edition reports no network while the
device network is otherwise working, and logcat shows TTNet dropping requests:

```text
ERR_TTNET_TRAFFIC_CONTROL_DROP
InternalErrorCode=-555
dns=-1, connect=-1, ssl=-1
```

The package targeted by this module is:

```text
com.zhiliaoapp.musically
```

This is not a general TikTok unlock module. If logcat shows DNS failures,
TLS errors, proxy errors, HTTP 4xx/5xx responses, or Android network policy
blocks, this module is probably not the right fix.

## What It Changes

TikTok stores TTNet runtime configuration under its private data directory.
This module checks these files:

```text
/data/data/com.zhiliaoapp.musically/files/server.json
/data/data/com.zhiliaoapp.musically/files/tt_net_config.config
```

It removes only the known global drop rule:

```text
rule_id=3011076
service_name="drop flow"
host_group=["*"]
contain_group=["/"]
drop=1
possibility=100
```

In plain terms, that rule means:

```text
Drop all hosts, all paths, 100% of the time.
```

The module runs once during boot and then keeps checking in the background,
because TikTok may rewrite TTNet config after launch.

Backups are created once next to the original files:

```text
server.json.fuck_ttnet.bak
tt_net_config.config.fuck_ttnet.bak
```

After patching, the module restores TikTok file ownership, mode `0600`, and
SELinux context with `restorecon`.

## Install

Install `fuck_ttnet-v1.0.2.zip` in KernelSU Manager and reboot.

After reboot, force-stop and reopen TikTok:

```sh
adb shell am force-stop com.zhiliaoapp.musically
```

The module also exposes an action script, so it can be triggered manually from
KernelSU Manager if supported by the manager version.

## Verify

Module log:

```text
/data/adb/modules/fuck_ttnet/fuck_ttnet.log
```

Useful logcat check:

```sh
adb logcat -d -v time \
  | grep -E 'ERR_TTNET|TRAFFIC_CONTROL|InternalErrorCode=-555|http code=200'
```

Before the fix, the important signal is a local TTNet drop:

```text
ERR_TTNET_TRAFFIC_CONTROL_DROP
InternalErrorCode=-555
dns=-1, connect=-1, ssl=-1
```

After the fix, TikTok should make real network requests again. Typical
successful lines include:

```text
http code=200
request fetch task succeeded
```

## Restore

Disable or uninstall the module from KernelSU Manager if it is no longer
needed.

To restore TikTok's backed-up TTNet files manually, copy the `.fuck_ttnet.bak`
files back over the original files, then restore ownership and SELinux context.
In most cases it is simpler to clear TikTok data or reinstall TikTok if a full
reset is desired.

## Root Cause

This issue is not the same as the phone having no internet.

Normal request flow:

```text
TikTok -> DNS -> TCP connect -> TLS -> request/response
```

In the failing state, TTNet rejects the request before DNS:

```text
TikTok -> TTNet local traffic-control drop
```

That is why the log reports `dns=-1`, `connect=-1`, and `ssl=-1`. The request
never leaves TikTok, so changing router rules or Android network permissions
does not fix this specific failure.

The exact reason TikTok receives or keeps this TTNet rule is server-side and
not fully observable from the device. Plausible inputs include account region,
store region, carrier region, proxy exit region, SIM/network country, device
history, and cached TTNet policy state. During investigation, locale/timezone
and carrier-facing request parameters were already changed to Japan, but TikTok
still returned `-555` until the local drop rule was removed.

The confirmed local cause is the cached `rule_id=3011076` global drop flow.
Removing that rule changed TTNet behavior from local `-555` drops to real
network responses such as `http code=200`.

## Scope And Limits

- Only TikTok international edition is targeted.
- Only `rule_id=3011076` global `drop flow` is removed.
- The module does not spoof SIM, account region, device model, or Play Store
  install source.
- If TikTok changes the rule ID or the TTNet config format, the matcher may
  need to be updated.
- If TikTok server-side policy blocks the account after the request reaches the
  server, this module will not bypass that response.
