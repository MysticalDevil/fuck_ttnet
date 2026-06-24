#!/usr/bin/env sh

# Collect read-only TTNet evidence from a rooted Android device.
#
# Inputs:
#   ADB       adb executable. Defaults to adb, or ~/Android/Sdk/platform-tools/adb.
#   $1        optional adb serial.
#   $2        optional output directory.
#
# Expected output:
#   A local evidence directory containing hit counts, file metadata, extracted
#   rule actions, and filtered logcat. The script does not modify device files
#   and does not copy full TTNet config files by default.

set -eu

RULE_ID="${RULE_ID:-3011076}"
PKG="${PKG:-com.zhiliaoapp.musically}"
SERIAL="${1:-}"
OUT_DIR="${2:-}"

if [ -z "${ADB:-}" ]; then
  if [ -x "$HOME/Android/Sdk/platform-tools/adb" ]; then
    ADB="$HOME/Android/Sdk/platform-tools/adb"
  else
    ADB="adb"
  fi
fi

if [ -z "$OUT_DIR" ]; then
  timestamp="$(date +%Y%m%d_%H%M%S)"
  OUT_DIR="/tmp/fuck_ttnet_evidence_$timestamp"
fi

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
EXTRACTOR="$ROOT_DIR/scripts/extract_ttnet_rule.py"

run_adb() {
  if [ -n "$SERIAL" ]; then
    "$ADB" -s "$SERIAL" "$@" </dev/null
  else
    "$ADB" "$@" </dev/null
  fi
}

adb_su() {
  run_adb shell su -c "$1"
}

adb_exec_su() {
  run_adb exec-out su -c "$1"
}

remote_files() {
  printf '%s\n' \
    "/data/data/$PKG/files/server.json" \
    "/data/data/$PKG/files/tt_net_config.config" \
    "/data/data/$PKG/files/server.json.bak_" \
    "/data/data/$PKG/files/tt_net_config.config.bak_"
}

mkdir -p "$OUT_DIR/rules"

{
  echo "created_at=$(date -Iseconds)"
  echo "adb=$ADB"
  echo "serial=${SERIAL:-default}"
  echo "package=$PKG"
  echo "rule_id=$RULE_ID"
} > "$OUT_DIR/metadata.txt"

run_adb devices -l > "$OUT_DIR/adb_devices.txt"

counts_file="$OUT_DIR/rule_hits.tsv"
info_file="$OUT_DIR/file_info.tsv"
printf 'hits\tpath\n' > "$counts_file"
printf 'size_bytes\tpath\n' > "$info_file"

remote_files | while IFS= read -r file; do
  if adb_su "[ -e '$file' ]"; then
    hits="$(adb_su "grep -o '$RULE_ID' '$file' 2>/dev/null | wc -l" | tr -d '[:space:]')"
    size="$(adb_su "wc -c < '$file' 2>/dev/null" | tr -d '[:space:]')"
    printf '%s\t%s\n' "$hits" "$file" >> "$counts_file"
    printf '%s\t%s\n' "$size" "$file" >> "$info_file"

    if [ "$hits" != "0" ]; then
      safe_name="$(printf '%s' "$file" | sed 's#[^A-Za-z0-9_.-]#_#g')"
      rule_output="$OUT_DIR/rules/$safe_name.rule.json"
      error_output="$OUT_DIR/rules/$safe_name.extract_error.txt"
      if adb_exec_su "cat '$file'" |
        python3 "$EXTRACTOR" --input - --rule-id "$RULE_ID" \
          > "$rule_output" 2> "$error_output"; then
        rm -f "$error_output"
        :
      else
        rm -f "$rule_output"
        {
          echo "collect: structured extraction failed for $file"
          echo "collect: the file may not be JSON; hit counts still apply"
          echo
          cat "$error_output"
        } > "$error_output.tmp"
        mv "$error_output.tmp" "$error_output"
      fi
    fi
  else
    printf 'missing\t%s\n' "$file" >> "$counts_file"
    printf 'missing\t%s\n' "$file" >> "$info_file"
  fi
done

run_adb logcat -d -v time 2>/dev/null |
  grep -E 'ERR_TTNET|TRAFFIC_CONTROL|InternalErrorCode=-555|dns=-1|connect=-1|ssl=-1|3011076' \
    > "$OUT_DIR/logcat_ttnet_filtered.txt" ||
  true

echo "collect: wrote $OUT_DIR"
