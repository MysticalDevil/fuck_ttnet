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
  case_dir_name="${6:-$1}"

  case_dir="$WORK_DIR/$case_dir_name"
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

# Regression guard for the E2BIG defect.
#
# On Android, `dumpsys connectivity` exceeds MAX_ARG_STRLEN (128 KiB). The old
# implementation captured it into a shell variable and passed that variable to
# printf as a single argument, which mksh rejects:
#
#   /system/bin/printf: Argument list too long
#
# Every one of those calls failed, the function fell through to 'unknown', and
# the `device_network_unvalidated` diagnosis became unreachable on real
# devices. Linux hosts are far more permissive about argument size, so a host
# test cannot make that exec fail; what it can do is pin the structure that
# made it fail. scripts/verify_e2big_boundary.sh proves the boundary on a
# real device.
assert_uses_file_redirection() {
  body="$(
    sed -n '/^default_network_validated() {/,/^}/p' "$ROOT_DIR/scripts/status.sh"
  )"

  if [ -z "$body" ]; then
    printf 'test: could not extract default_network_validated() from status.sh\n' >&2
    exit 1
  fi

  if printf '%s\n' "$body" | grep -q 'printf .*"\$connectivity_dump"'; then
    printf 'test: default_network_validated() passes the whole dumpsys as an argument\n' >&2
    printf 'test: that is the 128 KiB E2BIG defect; keep the dump on disk\n' >&2
    exit 1
  fi

  if printf '%s\n' "$body" | grep -q 'connectivity_dump='; then
    printf 'test: default_network_validated() still captures dumpsys into a variable\n' >&2
    exit 1
  fi

  if ! printf '%s\n' "$body" | grep -q 'grep -Eq .*"\$connectivity_file"'; then
    printf 'test: default_network_validated() no longer reads the dump from a file\n' >&2
    exit 1
  fi

  if printf '%s\n' "$body" | grep -q 'active_block" | grep -q'; then
    printf 'test: default_network_validated() still pipes active_block through printf\n' >&2
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

# Oversized dumpsys: the active network's VALIDATED flag sits far past where a
# 128 KiB single-argument limit would truncate the payload.
oversized_dumpsys_file="$WORK_DIR/oversized_dumpsys.txt"
{
  i=0
  while [ "$i" -lt 2400 ]; do
    printf '  filler record %s      NetworkRequest [ LISTEN id=1, [ Capabilities: INTERNET Uid: 1000 ] ]\n' "$i"
    i=$((i + 1))
  done
  printf '%s\n' 'Active default network: 100'
  printf '%s\n' '  NetworkAgentInfo{network{100} handle{1} ni{WIFI CONNECTED}}'
  printf '%s\n' '    nc{[ Transports: WIFI Capabilities: INTERNET&TRUSTED&VALIDATED ]}'
} > "$oversized_dumpsys_file"

oversized_size="$(wc -c < "$oversized_dumpsys_file" | tr -d ' ')"
if [ "$oversized_size" -le 131072 ]; then
  printf 'test: oversized dumpsys is only %s bytes; must exceed 131072\n' \
    "$oversized_size" >&2
  exit 1
fi

run_case \
  "oversized_validated_default_network" \
  '06-28 12:00:00.000  1111  2222 I ActivityManager: TikTok says No internet connection right now' \
  "$(cat "$oversized_dumpsys_file")" \
  "ui_only_generic_or_region_unavailable" \
  "yes" \
  "oversized"

assert_uses_file_redirection

echo "test: status network validation passed"
