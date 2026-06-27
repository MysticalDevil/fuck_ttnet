# TikTok No-Network Case Map

This repository started from one specific fix: removing a cached TTNet drop
rule (`3011076`). That is only one class of TikTok "no network" failure.

This note separates the known cases by:

- observable error signature
- likely mechanism
- evidence quality
- whether the case is locally reproducible here
- whether a local module can fix it

[中文版本](no-network-cases.zh-CN.md)

## Evidence Levels

- `Proven locally`: reproduced on the device used for this repository, with
  device files or logs preserved.
- `Externally supported`: backed by official TikTok material or primary
  research, but not fully re-run on this device.
- `User-reported`: plausible, but not strong enough to treat as established.

## Summary Table

| Case | Typical signature | Mechanism | Evidence | Repro here | Locally fixable |
| --- | --- | --- | --- | --- | --- |
| Device network not validated | Android shows Wi-Fi without internet, other apps partially break too | System network, DNS, captive portal, or proxy health issue | Proven locally | Yes | No |
| Local TTNet dispatch drop | `ERR_TTNET_TRAFFIC_CONTROL_DROP`, `InternalErrorCode=-555`, `dns=-1 connect=-1 ssl=-1` | Cached TNC/TTNet rule drops request before network I/O | Proven locally | Yes | Yes |
| TLS trust / proxy certificate failure | `net::ERR_CERT_AUTHORITY_INVALID`, `InternalErrorCode=-202`, real DNS/connect/SSL timing | TLS handshake fails in TTNet/Cronet | Proven locally | Yes | No |
| Region stopped operation / market withdrawal | Generic "No internet connection" or region-unavailable UI | Service intentionally unavailable for that region | Externally supported | Not re-run | Usually no |
| SIM/IP-driven server-side region enforcement | Region signals like SIM/IP/carrier feed server-side policy | App/server rejects usage based on region signals | Externally supported | Not re-run | Usually no |

## Case 0: Device Network Not Validated

### Case 0 Signature

- Android itself marks the default network as not validated.
- Wi-Fi UI can show "connected, no internet" or equivalent.
- Other apps may partially work, but images, avatars, or background fetches
  fail.
- TikTok-specific logs are often weak or inconsistent because the network is
  already unhealthy.

### Case 0 Mechanism

This is below TikTok. DNS, captive portal state, router policy, proxy health,
or system connectivity validation is already broken before any TTNet-specific
logic matters.

### Case 0 Evidence

- Proven locally in this repository's environment: after a reboot on
  **2026-06-27**, Android switched back to `VALIDATED` and TikTok immediately
  stopped emitting the previous `-202` signature.

### Case 0 Reproduction Status

- Proven locally.

### Case 0 Local Fixability

- No, not by this module.
- The right fix is at the device, Wi-Fi, DNS, router, or proxy layer.

## Case 1: Local TTNet Dispatch Drop

### Case 1 Signature

- `ERR_TTNET_TRAFFIC_CONTROL_DROP`
- `InternalErrorCode=-555`
- `dns=-1`, `connect=-1`, `ssl=-1`
- local TikTok files contain a dispatch action such as:
  - `rule_id=3011076`
  - `action="tc"`
  - `drop=1`
  - wildcard host/path match

### Case 1 Mechanism

TTNet loads cached TNC dispatch policy from local storage and can drop a
request before DNS, TCP connect, or TLS starts. In the observed case, the rule
body was a global drop action.

### Case 1 Evidence

- White-box investigation: [investigation.md](investigation.md)
- Module fix removes the local rule from:
  - `/data/data/com.zhiliaoapp.musically/files/server.json`
  - `/data/data/com.zhiliaoapp.musically/files/tt_net_config.config`

### Case 1 Reproduction Status

- Proven locally.
- True reproduction exists in this repository: inject or preserve the local
  dispatch rule, then observe `-555`.
- The current module and WebUI already verify this case.

### Case 1 Local Fixability

- Yes.
- This repository's KernelSU module is aimed at this class only.

## Case 2: TLS Trust / Proxy Certificate Failure

### Case 2 Signature

- `net::ERR_CERT_AUTHORITY_INVALID`
- `ErrorCode=11`
- `InternalErrorCode=-202`
- request attempts reach real remote IPs
- DNS/connect/SSL timing is present instead of `-1`

Observed on the current device on **2026-06-27** after launching TikTok:

- `current_region=CN`
- `sys_region=JP`
- `mcc_mnc=46011`
- `carrier_region=HK`
- `carrier_region_v2=454`
- `residence=HK`
- `op_region=HK`

Sample log excerpt:

- [samples/observed_err_cert_authority_invalid.log](../samples/observed_err_cert_authority_invalid.log)

### Case 2 Mechanism

This is not a local TTNet dispatch drop. TTNet/Cronet reaches the TLS stage,
then rejects the certificate chain. Chromium defines `ERR_CERT_AUTHORITY_INVALID`
as net error `-202`.

Supporting source:

- Chromium net error list:
  <https://chromium.googlesource.com/chromium/src/+/main/net/base/net_error_list.h>

### Case 2 Important Distinction

The presence of `carrier_region=HK` or `op_region=HK` in logs does **not** mean
the failure is automatically `3011076`. In the current reproduction, the app is
reaching network I/O and failing during certificate validation.

### Case 2 Reproduction Status

- Proven locally on the current device.
- Reproduced by clearing logcat, launching TikTok, and capturing fresh logs.

Use:

```sh
scripts/diagnose_no_network.sh
```

Current script behavior note:

- it no longer clears the device's whole logcat buffer
- it writes a temporary marker and prefers logs after that marker when pid
  filtering is unavailable

### Case 2 Local Fixability

- No, not with the current module.
- This usually points to proxy TLS interception, an untrusted CA, or a broken
  certificate chain on the network path.

## Case 3: Region Stopped Operation / Market Withdrawal

### Case 3 Signature

- Often presented to the user as generic no-network or region-unavailable UI.
- Public exact internal TTNet/Cronet error code is still not established.
- The current APK contains user-facing strings including:
  - `No internet connection`
  - `This feature is temporarily unavailable`
  - `Widget not available in your region.`

### Case 3 Mechanism

This is a product-availability decision, not necessarily a transport failure
and not necessarily a local TTNet drop. The app or backend can refuse service
for a region even when raw connectivity works.

### Case 3 Evidence

- TikTok told Axios in July 2020: "we've decided to stop operations of the
  TikTok app in Hong Kong."
- SCMP documented that the installed app blocked users with a Hong Kong SIM or
  Hong Kong IP and showed a no-internet experience.
- TikTok support says account region is determined from location signals such as
  SIM region and IP, and that some features are not available in all regions.

Sources:

- <https://www.axios.com/2020/07/07/tiktok-to-pull-out-of-hong-kong>
- <https://www.scmp.com/abacus/tech/article/3092574/tiktok-has-officially-pulled-out-hong-kong-you-can-still-use-it-if-you>
- <https://support.tiktok.com/ar/account-and-privacy/account-information/account-region>

### Case 3 Reproduction Status

- Strong external support.
- Not re-run end to end in this repository as a clean historical reproduction.

### Case 3 Local Fixability

- Usually no.
- Removing a cached local rule helps only if the no-network state is actually a
  local TTNet drop and not a region-availability decision.

## Case 4: SIM/IP-Driven Server-Side Region Enforcement

### Case 4 Signature

- VPN alone may not be enough.
- Region signals such as SIM country, carrier region, and IP region influence
  the policy decision.
- Public exact TikTok internal error code is not clearly documented.

### Case 4 Mechanism

Primary research on TikTok's India ban found app-side and server-side region
enforcement based on SIM-derived signals. The app can inspect SIM country and
the server can make policy decisions from transmitted region metadata.

This matches the signal family visible in current local TikTok logs:

- `carrier_region`
- `carrier_region_v2`
- `mcc_mnc`
- `op_region`
- `residence`

### Case 4 Evidence

The PAM 2024 paper reports:

- TikTok calls `getSimCountryISO`.
- A modified APK that changed `carrier_region=IN` to `carrier_region=US` and
  always returned `US` from `getSimCountryISO` was able to function again.
- Merely using a VPN was insufficient while the Indian SIM remained present.

Primary source:

- <https://www.devashishgosain.com/assets/files/On_app_filtering_in_India_PAM_24_Camera_Ready.pdf>

### Case 4 Reproduction Status

- Strong primary-research support.
- Not fully reproduced on this repository's device yet.
- Injection-only demos are not enough for this case, because the critical
  decision is server-side.

### Case 4 Local Fixability

- Usually no single local fix.
- If the server has already pushed a local TTNet drop rule, the module can
  remove that local symptom. It cannot override the underlying server-side
  policy decision.

## Practical Triage

When TikTok says "no network", check these in order:

1. If Android itself says the default network is not validated, fix device or
   router connectivity first.
2. If logs show `ERR_TTNET_TRAFFIC_CONTROL_DROP` and `-555`, treat it as a
   local TTNet drop.
3. If logs show `ERR_CERT_AUTHORITY_INVALID` and `-202`, treat it as a TLS or
   proxy trust problem.
4. If logs show real HTTP responses or region-unavailable UI without `-555`,
   suspect server-side region policy.
5. If only UI strings are visible and there is no strong log signature yet,
   capture fresh logs before changing random settings.

The repository helper for quick classification is:

```sh
scripts/diagnose_no_network.sh
```
