#!/usr/bin/env sh

set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fuck_ttnet_redaction_test.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT HUP INT TERM

create_stub_commands() {
  bin_dir="$1"
  log_file="$2"

  mkdir -p "$bin_dir"

  printf '%s\n' '#!/usr/bin/env sh' 'exit 0' > "$bin_dir/pidof"
  printf '%s\n' '#!/usr/bin/env sh' "cat \"\$LOG_SOURCE\"" > "$bin_dir/logcat"
  printf '%s\n' '#!/usr/bin/env sh' 'printf "%s\n" "Capabilities: INTERNET&VALIDATED"' > "$bin_dir/dumpsys"
  printf '%s\n' '#!/usr/bin/env sh' 'shift; exec "$@"' > "$bin_dir/timeout"
  printf '%s\n' '#!/usr/bin/env sh' 'exec /usr/bin/strings "$@"' > "$bin_dir/strings"

  chmod +x \
    "$bin_dir/pidof" \
    "$bin_dir/logcat" \
    "$bin_dir/dumpsys" \
    "$bin_dir/timeout" \
    "$bin_dir/strings"

  export LOG_SOURCE="$log_file"
}

prepare_moddir() {
  moddir="$1"
  mkdir -p "$moddir/common"
  printf '%s\n' 'version=v1.1.1-test' > "$moddir/module.prop"
  cp "$ROOT_DIR/common/count_global_drop.awk" "$moddir/common/count_global_drop.awk"
}

case_dir="$WORK_DIR/redaction"
moddir="$case_dir/mod"
appdir="$case_dir/app"
bindir="$case_dir/bin"
logfile="$case_dir/logcat.txt"

mkdir -p "$case_dir" "$appdir/files"
cat <<'EOF' > "$logfile"
06-28 12:00:00.000  1111  2222 I TTNet: url=https://api16-normal-c-useast1a.tiktokv.com/aweme/v1/feed/?carrier_region=HK&carrier_region_v2=454&mcc_mnc=23410&device_id=1234567890123456789&iid=9876543210123456789&sessionid=secret-session-value
06-28 12:00:01.000  1111  2222 E CronetUrlRequest: net_error -202, InternalErrorCode=-202, net::ERR_CERT_AUTHORITY_INVALID
EOF

prepare_moddir "$moddir"
create_stub_commands "$bindir" "$logfile"

output="$(
  PATH="$bindir:$PATH" \
    MODDIR="$moddir" \
    APP_DIR="$appdir" \
    FILES_DIR="$appdir/files" \
    sh "$ROOT_DIR/scripts/status.sh"
)"

assert_contains() {
  needle="$1"
  if ! printf '%s\n' "$output" | grep -Fq "$needle"; then
    printf 'test: expected output to contain %s\n' "$needle" >&2
    exit 1
  fi
}

assert_not_contains() {
  needle="$1"
  if printf '%s\n' "$output" | grep -Fq "$needle"; then
    printf 'test: expected output to redact %s\n' "$needle" >&2
    exit 1
  fi
}

assert_contains 'carrier_region=HK'
assert_contains 'carrier_region_v2=454'
assert_contains 'mcc_mnc=23410'
assert_contains 'device_id=[REDACTED]'
assert_contains 'iid=[REDACTED]'
assert_contains 'sessionid=[REDACTED]'
assert_not_contains 'device_id=1234567890123456789'
assert_not_contains 'iid=9876543210123456789'
assert_not_contains 'sessionid=secret-session-value'

# The query-string form above was the only shape the original patterns caught.
# These are the shapes observed on a real device that used to pass through
# unredacted: a bare key=value params dump, a dash header, a JSON value under a
# different key, and the TNC `&#*` separator used by tt_net_config.config.
redaction_probe="$WORK_DIR/redaction_probe.sh"

{
  printf '%s\n' '#!/usr/bin/env sh'
  printf '%s\n' 'REDACTED_VALUE="[REDACTED]"'
  sed -n '/^sanitize_log_block() {/,/^}/p' "$ROOT_DIR/scripts/status.sh"
  printf '%s\n' 'sanitize_log_block "$1"'
} > "$redaction_probe"

check_redacted() {
  label="$1"
  input="$2"
  secret="$3"
  probe_out="$(sh "$redaction_probe" "$input")"

  case "$probe_out" in
    *"[REDACTED]"*) : ;;
    *)
      printf 'test: %s was not redacted\n  in : %s\n  out: %s\n' \
        "$label" "$input" "$probe_out" >&2
      exit 1
      ;;
  esac

  case "$probe_out" in
    *"$secret"*)
      printf 'test: %s leaked %s\n  out: %s\n' "$label" "$secret" "$probe_out" >&2
      exit 1
      ;;
    *) : ;;
  esac
}

check_kept() {
  label="$1"
  input="$2"
  kept="$3"
  probe_out="$(sh "$redaction_probe" "$input")"

  case "$probe_out" in
    *"$kept"*) : ;;
    *)
      printf 'test: %s over-redacted and lost %s\n  in : %s\n  out: %s\n' \
        "$label" "$kept" "$input" "$probe_out" >&2
      exit 1
      ;;
  esac
}

check_redacted 'bare params dump (device_id)' \
  'CommonParams{device_id=7123456789, iid=9876543210, carrier_region=HK}' '7123456789'
check_redacted 'bare params dump (iid)' \
  'CommonParams{device_id=7123456789, iid=9876543210, carrier_region=HK}' '9876543210'
check_redacted 'spaces around equals' \
  'device_id = 123456789' '123456789'
check_redacted 'dash header (x-tt-token)' \
  'x-tt-token: abcSECRET123 end' 'abcSECRET123'
check_redacted 'colon form (sessionid)' \
  'sessionid: 0a1b2c3d4e5f' '0a1b2c3d4e5f'
check_redacted 'json value (sec_uid)' \
  '{"sec_uid":"MS4wLjABAAAAsecretvalue","status":1}' 'MS4wLjABAAAAsecretvalue'
check_redacted 'TNC separator (device_id)' \
  'device_id&#*7451564133168743978@$*received_region_config&#*1' '7451564133168743978'
check_redacted 'TNC separator (store_sec_uid)' \
  'store_sec_uid&#*MS4wLjABAAAAsecretvalue@$*tnc_abtest&#*1' 'MS4wLjABAAAAsecretvalue'
check_redacted 'authorization header' \
  'Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig' 'eyJhbGciOiJIUzI1NiJ9'
check_redacted 'cookie header' \
  'Cookie: sessionid=abc; sid_tt=def' 'sessionid=abc'

# Redaction must not destroy the evidence the module exists to report.
check_kept 'diagnostic region evidence' \
  'carrier_region=HK&mcc_mnc=45400&sys_region=US' 'carrier_region=HK'
check_kept 'diagnostic mcc_mnc' \
  'carrier_region=HK&mcc_mnc=45400&sys_region=US' 'mcc_mnc=45400'
check_kept 'diagnostic rule id' \
  'E TTNet: ERR_TTNET_TRAFFIC_CONTROL_DROP InternalErrorCode=-555 rule_id=3011076' '3011076'
check_kept 'diagnostic error code' \
  'E TTNet: ERR_TTNET_TRAFFIC_CONTROL_DROP InternalErrorCode=-555 rule_id=3011076' 'InternalErrorCode=-555'
check_kept 'diagnostic http status' \
  'http_request_status_code=403 cronet_internal_error_code=-202' 'http_request_status_code=403'
check_kept 'unrelated network uid' \
  'NetworkRequest [ LISTEN id=64, [ Capabilities: INTERNET&VALIDATED Uid: 1000 ] ]' 'Uid: 1000'

echo "test: status redaction passed"
