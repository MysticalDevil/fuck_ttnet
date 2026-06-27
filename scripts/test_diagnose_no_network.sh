#!/usr/bin/env sh

set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fuck_ttnet_diagnose_test.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT HUP INT TERM

adb_stub="$WORK_DIR/adb"
commands_log="$WORK_DIR/adb-commands.log"
stdout_log="$WORK_DIR/stdout.log"
stderr_log="$WORK_DIR/stderr.log"
marker_file="$WORK_DIR/marker.txt"

cat > "$adb_stub" <<'EOF'
#!/usr/bin/env sh
set -eu

commands_log="$ADB_COMMANDS_LOG"
marker_file="$ADB_MARKER_FILE"

printf '%s\n' "$*" >> "$commands_log"

if [ "$1" = "logcat" ] && [ "$2" = "-c" ]; then
  exit 0
fi

if [ "$1" = "shell" ] && [ "$2" = "am" ] && [ "$3" = "force-stop" ]; then
  exit 0
fi

if [ "$1" = "shell" ] && [ "$2" = "monkey" ]; then
  exit 0
fi

if [ "$1" = "shell" ] && [ "$2" = "pidof" ]; then
  exit 0
fi

if [ "$1" = "shell" ] && [ "$2" = "log" ]; then
  printf '%s\n' "$5" > "$marker_file"
  exit 0
fi

if [ "$1" = "logcat" ] && [ "$2" = "-d" ] && [ "$3" = "-v" ] && [ "$4" = "time" ]; then
  marker="$(cat "$marker_file" 2>/dev/null || true)"
  printf '%s\n' '06-28 11:59:59.000  1000  1000 I OldTag: unrelated-before-marker'
  if [ -n "$marker" ]; then
    printf '06-28 12:00:00.000  1000  1000 I FuckTTNet: %s\n' "$marker"
  fi
  printf '%s\n' '06-28 12:00:01.000  1111  2222 E TTNet: ERR_TTNET_TRAFFIC_CONTROL_DROP InternalErrorCode=-555'
  exit 0
fi

printf 'unexpected adb invocation: %s\n' "$*" >&2
exit 1
EOF

chmod +x "$adb_stub"

ADB_COMMANDS_LOG="$commands_log" \
ADB_MARKER_FILE="$marker_file" \
ADB="$adb_stub" \
WAIT_SECONDS=0 \
sh "$ROOT_DIR/scripts/diagnose_no_network.sh" >"$stdout_log" 2>"$stderr_log"

assert_stdout_contains() {
  needle="$1"
  if ! grep -Fq "$needle" "$stdout_log"; then
    printf 'test: expected stdout to contain %s\n' "$needle" >&2
    cat "$stdout_log" >&2
    exit 1
  fi
}

assert_stdout_not_contains() {
  needle="$1"
  if grep -Fq "$needle" "$stdout_log"; then
    printf 'test: expected stdout to omit %s\n' "$needle" >&2
    cat "$stdout_log" >&2
    exit 1
  fi
}

assert_commands_not_contains() {
  needle="$1"
  if grep -Fq "$needle" "$commands_log"; then
    printf 'test: expected adb commands to omit %s\n' "$needle" >&2
    cat "$commands_log" >&2
    exit 1
  fi
}

assert_stdout_contains 'classification: local_ttnet_drop'
assert_stdout_not_contains 'unrelated-before-marker'
assert_commands_not_contains 'logcat -c'

echo "test: diagnose_no_network passed"
