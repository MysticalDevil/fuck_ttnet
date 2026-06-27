#!/usr/bin/env sh

# Capture a fresh TikTok launch and classify common "no network" signatures.
#
# Usage:
#   scripts/diagnose_no_network.sh
#   ADB=/path/to/adb WAIT_SECONDS=10 scripts/diagnose_no_network.sh
#
# Output:
#   - one-line classification
#   - matching log excerpts for TTNet/Cronet/region signals

set -eu

ADB="${ADB:-$HOME/Android/Sdk/platform-tools/adb}"
PKG="${PKG:-com.zhiliaoapp.musically}"
WAIT_SECONDS="${WAIT_SECONDS:-12}"
TIKTOK_EVIDENCE_PATTERN='tiktokv|aweme/|com\.ttnet|carrier_region|carrier_region_v2|mcc_mnc|op_region|residence|current_region|sys_region|cronet_internal_error_code|http_request_status_code|ExploreTopicFeedApi|musically'

if [ ! -x "$ADB" ]; then
  echo "diagnose: adb not found: $ADB" >&2
  exit 1
fi

tmp_log="$(mktemp "${TMPDIR:-/tmp}/fuck_ttnet_diagnose.XXXXXX")"
cleanup() {
  rm -f "$tmp_log"
}
trap cleanup EXIT INT TERM

echo "diagnose: clearing logcat"
"$ADB" logcat -c

echo "diagnose: force-stopping $PKG"
"$ADB" shell am force-stop "$PKG" >/dev/null

echo "diagnose: launching $PKG"
"$ADB" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null

echo "diagnose: waiting ${WAIT_SECONDS}s"
sleep "$WAIT_SECONDS"

echo "diagnose: collecting logcat"
pid="$("$ADB" shell pidof -s "$PKG" | tr -d '\r')"
if [ -n "$pid" ]; then
  echo "diagnose: using pid $pid"
  "$ADB" logcat -d --pid="$pid" -v time > "$tmp_log"
else
  echo "diagnose: pid not found, falling back to full logcat with TikTok evidence filter"
  "$ADB" logcat -d -v time | grep -E "$TIKTOK_EVIDENCE_PATTERN|ERR_TTNET|InternalErrorCode=-555|ERR_CERT_AUTHORITY_INVALID|InternalErrorCode=-202|No internet connection|temporarily unavailable|not available in your region" > "$tmp_log" || true
fi

classification="unknown"
reason="no known signature matched"

if rg -q 'ERR_TTNET_TRAFFIC_CONTROL_DROP|InternalErrorCode=-555' "$tmp_log"; then
  classification="local_ttnet_drop"
  reason="matched ERR_TTNET_TRAFFIC_CONTROL_DROP / -555"
elif rg -q 'ERR_CERT_AUTHORITY_INVALID|InternalErrorCode=-202' "$tmp_log"; then
  classification="tls_cert_authority_invalid"
  reason="matched ERR_CERT_AUTHORITY_INVALID / -202"
elif rg -q 'No internet connection|temporarily unavailable|not available in your region' "$tmp_log"; then
  classification="ui_only_generic_or_region_unavailable"
  reason="matched user-facing no-network or region strings without a stronger transport signature"
fi

echo "classification: $classification"
echo "reason: $reason"
echo
echo "relevant log excerpts:"
rg -n \
  'ERR_TTNET|InternalErrorCode|ERR_CERT_AUTHORITY_INVALID|carrier_region|carrier_region_v2|mcc_mnc|op_region|residence|current_region|sys_region|No internet connection|temporarily unavailable|not available in your region|http_request_status_code|cronet_internal_error_code' \
  "$tmp_log" | head -n 120 || true
