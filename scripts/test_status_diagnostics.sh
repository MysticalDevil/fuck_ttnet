#!/usr/bin/env sh

set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fuck_ttnet_status_test.XXXXXX")"

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

run_case() {
  case_name="$1"
  log_body="$2"
  expected_diagnosis="$3"
  expected_count_key="$4"

  case_dir="$WORK_DIR/$case_name"
  moddir="$case_dir/mod"
  appdir="$case_dir/app"
  bindir="$case_dir/bin"
  logfile="$case_dir/logcat.txt"

  mkdir -p "$case_dir" "$appdir/files"
  printf '%s\n' "$log_body" > "$logfile"
  prepare_moddir "$moddir"
  create_stub_commands "$bindir" "$logfile"

  output="$(
    PATH="$bindir:$PATH" \
      MODDIR="$moddir" \
      APP_DIR="$appdir" \
      FILES_DIR="$appdir/files" \
      sh "$ROOT_DIR/scripts/status.sh"
  )"

  diagnosis="$(printf '%s\n' "$output" | sed -n 's/^diagnosis_id=//p' | head -n 1)"
  if [ "$diagnosis" != "$expected_diagnosis" ]; then
    printf 'test: %s expected diagnosis %s, got %s\n' \
      "$case_name" "$expected_diagnosis" "$diagnosis" >&2
    exit 1
  fi

  count_value="$(printf '%s\n' "$output" | sed -n "s/^$expected_count_key=//p" | head -n 1)"
  if [ "${count_value:-0}" = "0" ]; then
    printf 'test: %s expected non-zero %s\n' "$case_name" "$expected_count_key" >&2
    exit 1
  fi
}

run_case \
  "tls_only" \
  '06-28 12:00:00.000  1111  2222 E CronetUrlRequest: net_error -202, InternalErrorCode=-202, net::ERR_CERT_AUTHORITY_INVALID' \
  "tls_cert_authority_invalid" \
  "recent_tls_error_count"

run_case \
  "ui_only" \
  '06-28 12:00:00.000  1111  2222 I ActivityManager: TikTok says No internet connection right now' \
  "ui_only_generic_or_region_unavailable" \
  "recent_ui_signal_count"

echo "test: status diagnostics passed"
