#!/usr/bin/env sh

set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fuck_ttnet_network_validation_test.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT HUP INT TERM

create_stub_commands() {
  bin_dir="$1"
  log_file="$2"
  dumpsys_file="$3"

  mkdir -p "$bin_dir"

  printf '%s\n' '#!/usr/bin/env sh' 'exit 0' > "$bin_dir/pidof"
  printf '%s\n' '#!/usr/bin/env sh' "cat \"\$LOG_SOURCE\"" > "$bin_dir/logcat"
  printf '%s\n' '#!/usr/bin/env sh' "cat \"\$DUMPSYS_SOURCE\"" > "$bin_dir/dumpsys"
  printf '%s\n' '#!/usr/bin/env sh' 'shift; exec "$@"' > "$bin_dir/timeout"
  printf '%s\n' '#!/usr/bin/env sh' 'exec /usr/bin/strings "$@"' > "$bin_dir/strings"

  chmod +x \
    "$bin_dir/pidof" \
    "$bin_dir/logcat" \
    "$bin_dir/dumpsys" \
    "$bin_dir/timeout" \
    "$bin_dir/strings"

  export LOG_SOURCE="$log_file"
  export DUMPSYS_SOURCE="$dumpsys_file"
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
  dumpsys_body="$3"
  expected_diagnosis="$4"
  expected_network_state="$5"

  case_dir="$WORK_DIR/$case_name"
  moddir="$case_dir/mod"
  appdir="$case_dir/app"
  bindir="$case_dir/bin"
  logfile="$case_dir/logcat.txt"
  dumpsys_file="$case_dir/dumpsys.txt"

  mkdir -p "$case_dir" "$appdir/files"
  printf '%s\n' "$log_body" > "$logfile"
  printf '%s\n' "$dumpsys_body" > "$dumpsys_file"
  prepare_moddir "$moddir"
  create_stub_commands "$bindir" "$logfile" "$dumpsys_file"

  output="$(
    PATH="$bindir:$PATH" \
      MODDIR="$moddir" \
      APP_DIR="$appdir" \
      FILES_DIR="$appdir/files" \
      sh "$ROOT_DIR/scripts/status.sh"
  )"

  diagnosis="$(printf '%s\n' "$output" | sed -n 's/^diagnosis_id=//p' | head -n 1)"
  network_state="$(printf '%s\n' "$output" | sed -n 's/^network_validated=//p' | head -n 1)"

  if [ "$diagnosis" != "$expected_diagnosis" ]; then
    printf 'test: %s expected diagnosis %s, got %s\n' \
      "$case_name" "$expected_diagnosis" "$diagnosis" >&2
    exit 1
  fi

  if [ "$network_state" != "$expected_network_state" ]; then
    printf 'test: %s expected network_validated=%s, got %s\n' \
      "$case_name" "$expected_network_state" "$network_state" >&2
    exit 1
  fi
}

run_case \
  "no_default_network" \
  '06-28 12:00:00.000  1111  2222 I ActivityManager: TikTok says No internet connection right now' \
  'Active default network: none' \
  "device_network_unvalidated" \
  "no"

run_case \
  "other_network_validated_only" \
  '06-28 12:00:00.000  1111  2222 I ActivityManager: TikTok says No internet connection right now' \
  'Active default network: 100
Current Networks:
  NetworkAgentInfo [WIFI () - 100]
    NetworkCapabilities: INTERNET&TRUSTED
  NetworkAgentInfo [MOBILE () - 101]
    NetworkCapabilities: INTERNET&TRUSTED&VALIDATED' \
  "device_network_unvalidated" \
  "no"

echo "test: status network validation passed"
