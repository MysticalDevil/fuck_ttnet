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

echo "test: status redaction passed"
