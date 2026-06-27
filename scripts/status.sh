#!/system/bin/sh

MODDIR="${MODDIR:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}"
PKG="${PKG:-com.zhiliaoapp.musically}"
APP_DIR="${APP_DIR:-/data/data/$PKG}"
FILES_DIR="${FILES_DIR:-$APP_DIR/files}"
SERVER_JSON="${SERVER_JSON:-$FILES_DIR/server.json}"
TT_NET_CONFIG="${TT_NET_CONFIG:-$FILES_DIR/tt_net_config.config}"
LOG_FILE="${LOG_FILE:-$MODDIR/fuck_ttnet.log}"
COUNT_GLOBAL_DROP_AWK="${COUNT_GLOBAL_DROP_AWK:-$MODDIR/common/count_global_drop.awk}"
LOGCAT_LINES="${LOGCAT_LINES:-300}"
TIKTOK_EVIDENCE_PATTERN='tiktokv|aweme/|com\.ttnet|carrier_region|carrier_region_v2|mcc_mnc|op_region|residence|current_region|sys_region|cronet_internal_error_code|http_request_status_code|ExploreTopicFeedApi|musically'
TIKTOK_SIGNAL_PATTERN='ERR_TTNET|TRAFFIC_CONTROL|InternalErrorCode=-555|ERR_CERT_AUTHORITY_INVALID|InternalErrorCode=-202|No internet connection|temporarily unavailable|not available in your region'

count_literal() {
  file="$1"
  if [ ! -f "$file" ]; then
    printf '0'
    return
  fi
  grep -o '3011076' "$file" 2>/dev/null | wc -l | tr -d ' '
}

count_global_drop() {
  if [ ! -f "$SERVER_JSON" ] || [ ! -f "$COUNT_GLOBAL_DROP_AWK" ]; then
    printf '0'
    return
  fi
  if ! grep -q '3011076' "$SERVER_JSON" 2>/dev/null; then
    printf '0'
    return
  fi
  result="$(timeout "${STATUS_AWK_TIMEOUT:-3}" awk -f "$COUNT_GLOBAL_DROP_AWK" "$SERVER_JSON" 2>/dev/null | tail -n 1)"
  printf '%s' "${result:--1}"
}

file_mtime() {
  file="$1"
  if [ -f "$file" ]; then
    date -r "$file" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf 'unknown'
  else
    printf 'missing'
  fi
}

file_size() {
  file="$1"
  if [ -f "$file" ]; then
    wc -c < "$file" 2>/dev/null | tr -d ' '
  else
    printf '0'
  fi
}

strings_count() {
  path="$1"
  if [ ! -e "$path" ]; then
    printf '0'
    return
  fi
  strings "$path" 2>/dev/null | grep -o '3011076' | wc -l | tr -d ' '
}

pid_for_tiktok() {
  pidof "$PKG" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//'
}

default_network_validated() {
  if dumpsys connectivity 2>/dev/null | grep -q 'Capabilities: .*VALIDATED'; then
    printf 'yes'
  else
    printf 'no'
  fi
}

collect_logcat() {
  pid="$1"
  if [ -n "$pid" ]; then
    logcat -d --pid="$pid" -v time 2>/dev/null
  else
    logcat -d -v time -t "$LOGCAT_LINES" 2>/dev/null
  fi
}

latest_logcat_matches() {
  pid="$1"
  collect_logcat "$pid" |
    grep -E "$TIKTOK_SIGNAL_PATTERN|$TIKTOK_EVIDENCE_PATTERN" |
    tail -40
}

extract_param() {
  name="$1"
  line="$2"
  printf '%s' "$line" |
    sed -n "s/.*[?&]$name=\\([^&\" ]*\\).*/\\1/p" |
    tail -n 1
}

print_field() {
  key="$1"
  value="$2"
  printf '%s=%s\n' "$key" "$value" | tr '\n' '\n'
}

tiktok_pid="$(pid_for_tiktok)"
latest_matches="$(latest_logcat_matches "$tiktok_pid")"
latest_region_line="$(printf '%s\n' "$latest_matches" | grep -E 'carrier_region|mcc_mnc|current_region|sys_region' | tail -n 1)"
recent_error_count="$(printf '%s\n' "$latest_matches" | grep -c -E 'ERR_TTNET|TRAFFIC_CONTROL|InternalErrorCode=-555' 2>/dev/null)"
recent_tls_error_count="$(printf '%s\n' "$latest_matches" | grep -c -E 'ERR_CERT_AUTHORITY_INVALID|InternalErrorCode=-202' 2>/dev/null)"
recent_ui_signal_count="$(printf '%s\n' "$latest_matches" | grep -c -E 'No internet connection|temporarily unavailable|not available in your region' 2>/dev/null)"
server_rule_hits="$(count_global_drop)"
server_literal_hits="$(count_literal "$SERVER_JSON")"
config_hits="$(count_literal "$TT_NET_CONFIG")"
keva_tnc_hits="$(strings_count "$FILES_DIR/keva/repo/ttnet_tnc_config/tnc_config_str.sgv")"
keva_multi_hits="$(strings_count "$FILES_DIR/keva/repo/multi_process_config/tnc_config.sgv")"
network_validated="$(default_network_validated)"

status="clean"
diagnosis_id="healthy_or_no_recent_signature"
diagnosis_title="No Known Local TTNet Block"
transport_stage="none"
repair_action="none"
repairability="unsupported"
summary="No active 3011076 TTNet drop rule found, and no recent known no-network signature matched."
recommended_action="If TikTok still looks offline, collect a fresh launch trace and inspect proxy, region, and TLS signals."

if [ ! -d "$FILES_DIR" ]; then
  status="unknown"
  diagnosis_id="missing_tiktok_data"
  diagnosis_title="TikTok Data Not Initialized"
  transport_stage="unknown"
  repair_action="none"
  repairability="unsupported"
  summary="TikTok data directory is missing. Open TikTok once, then refresh."
  recommended_action="Launch TikTok once so the app creates its data directory."
elif [ "$server_rule_hits" -gt 0 ] 2>/dev/null || [ "$recent_error_count" -gt 0 ] 2>/dev/null; then
  status="blocked"
  diagnosis_id="local_ttnet_drop"
  diagnosis_title="Local TTNet Dispatch Drop"
  transport_stage="pre_network"
  repair_action="patch_local_ttnet"
  repairability="supported"
  summary="TTNet local drop is active or recent -555 drops were observed."
  recommended_action="Run the module repair to remove cached local TTNet drop metadata, then force-stop and reopen TikTok."
elif [ "$recent_tls_error_count" -gt 0 ] 2>/dev/null; then
  status="warning"
  diagnosis_id="tls_cert_authority_invalid"
  diagnosis_title="TLS Certificate Trust Failure"
  transport_stage="tls"
  repair_action="reset_runtime_cache"
  repairability="limited"
  summary="TikTok is reaching TLS and failing with ERR_CERT_AUTHORITY_INVALID / -202."
  recommended_action="Treat this as a proxy, CA trust, or network-path problem. A local cache reset may help, but patching 3011076 will not."
elif [ "$recent_ui_signal_count" -gt 0 ] 2>/dev/null; then
  status="warning"
  diagnosis_id="ui_only_generic_or_region_unavailable"
  diagnosis_title="Generic UI No-Network or Region Block"
  transport_stage="app_or_server_policy"
  repair_action="none"
  repairability="unsupported"
  summary="TikTok shows a generic no-network or region-unavailable UI string without a stronger local TTNet signature."
  recommended_action="Capture a fresh launch trace and verify whether this is region policy, market withdrawal, or another server-side restriction."
elif [ "$network_validated" = "no" ]; then
  status="warning"
  diagnosis_id="device_network_unvalidated"
  diagnosis_title="Android Default Network Is Not Validated"
  transport_stage="system_network"
  repair_action="none"
  repairability="unsupported"
  summary="Android does not currently consider the default network validated for internet access."
  recommended_action="Fix Wi-Fi, captive portal, DNS, or proxy health first. TikTok-specific repair is secondary until the device network is validated."
elif [ "$config_hits" -gt 0 ] 2>/dev/null || [ "$keva_tnc_hits" -gt 0 ] 2>/dev/null || [ "$keva_multi_hits" -gt 0 ] 2>/dev/null; then
  status="dirty"
  diagnosis_id="cached_ttnet_metadata"
  diagnosis_title="Cached TTNet Metadata Still Present"
  transport_stage="pre_network_cache"
  repair_action="patch_local_ttnet"
  repairability="supported"
  summary="3011076 remains in cached TNC metadata, but server.json has no active global drop."
  recommended_action="Run the module repair to clean stale cached TTNet metadata before it becomes an active local drop again."
fi

recent_errors="$(printf '%s\n' "$latest_matches" | grep -E 'ERR_TTNET|TRAFFIC_CONTROL|InternalErrorCode=-555' | tail -5)"
recent_tls_errors="$(printf '%s\n' "$latest_matches" | grep -E 'ERR_CERT_AUTHORITY_INVALID|InternalErrorCode=-202' | tail -5)"
recent_ui_signals="$(printf '%s\n' "$latest_matches" | grep -E 'No internet connection|temporarily unavailable|not available in your region' | tail -5)"
module_log="$(tail -12 "$LOG_FILE" 2>/dev/null)"

print_field "status" "$status"
print_field "summary" "$summary"
print_field "diagnosis_id" "$diagnosis_id"
print_field "diagnosis_title" "$diagnosis_title"
print_field "transport_stage" "$transport_stage"
print_field "repair_action" "$repair_action"
print_field "repairability" "$repairability"
print_field "recommended_action" "$recommended_action"
print_field "package" "$PKG"
print_field "module_version" "$(sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null | head -n 1)"
print_field "tiktok_pid" "${tiktok_pid:-not running}"
print_field "network_validated" "$network_validated"
print_field "server_json" "$SERVER_JSON"
print_field "tt_net_config" "$TT_NET_CONFIG"
print_field "server_global_drop_hits" "$server_rule_hits"
print_field "server_literal_hits" "$server_literal_hits"
print_field "tt_net_config_hits" "$config_hits"
print_field "keva_tnc_hits" "$keva_tnc_hits"
print_field "keva_multi_hits" "$keva_multi_hits"
print_field "recent_ttnet_error_count" "$recent_error_count"
print_field "recent_tls_error_count" "$recent_tls_error_count"
print_field "recent_ui_signal_count" "$recent_ui_signal_count"
print_field "server_json_mtime" "$(file_mtime "$SERVER_JSON")"
print_field "server_json_size" "$(file_size "$SERVER_JSON")"
print_field "tt_net_config_mtime" "$(file_mtime "$TT_NET_CONFIG")"
print_field "tt_net_config_size" "$(file_size "$TT_NET_CONFIG")"
print_field "carrier_region" "$(extract_param carrier_region "$latest_region_line")"
print_field "carrier_region_v2" "$(extract_param carrier_region_v2 "$latest_region_line")"
print_field "mcc_mnc" "$(extract_param mcc_mnc "$latest_region_line")"
print_field "region" "$(extract_param region "$latest_region_line")"
print_field "current_region" "$(extract_param current_region "$latest_region_line")"
print_field "sys_region" "$(extract_param sys_region "$latest_region_line")"
printf 'recent_errors<<EOF\n%s\nEOF\n' "$recent_errors"
printf 'recent_tls_errors<<EOF\n%s\nEOF\n' "$recent_tls_errors"
printf 'recent_ui_signals<<EOF\n%s\nEOF\n' "$recent_ui_signals"
printf 'latest_region_line<<EOF\n%s\nEOF\n' "$latest_region_line"
printf 'module_log<<EOF\n%s\nEOF\n' "$module_log"
