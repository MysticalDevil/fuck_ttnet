#!/usr/bin/env sh

# Probe the current TikTok dex for TTNet URL-dispatch evidence.
#
# Inputs:
#   BAKSMALI_JAR  path to baksmali jar, default /tmp/baksmali-2.5.2.jar
#   DEX_FILE      path to TikTok classes21.dex, default /tmp/tiktok_base_dex/classes21.dex
#   $1            output directory, default /tmp/fuck_ttnet_baksmali_current
#
# Expected output:
#   Prints key string/class hits and disassembles the TTNet classes used in the
#   investigation document.

set -eu

BAKSMALI_JAR="${BAKSMALI_JAR:-/tmp/baksmali-2.5.2.jar}"
DEX_FILE="${DEX_FILE:-/tmp/tiktok_base_dex/classes21.dex}"
OUT_DIR="${1:-/tmp/fuck_ttnet_baksmali_current}"

need_file() {
  if [ ! -f "$1" ]; then
    echo "probe: missing file: $1" >&2
    exit 1
  fi
}

need_file "$BAKSMALI_JAR"
need_file "$DEX_FILE"

echo "probe: baksmali:"
java -jar "$BAKSMALI_JAR" --version

echo
echo "probe: dex file: $DEX_FILE"
echo "probe: output dir: $OUT_DIR"

echo
echo "probe: key TTNet strings"
{
  java -jar "$BAKSMALI_JAR" list strings "$DEX_FILE" |
    grep -E 'DISPATCH_DROP|ERR_TTNET_TRAFFIC_CONTROL_DROP|ttnet_dispatch_actions|ttnet_dispatch_actions_epoch|drop_code|host_group|contain_group|rule_id' ||
    true
} |
  awk 'length($0) > 180 { print substr($0, 1, 177) "..."; next } { print }'

echo
echo "probe: expected current-APK classes"
java -jar "$BAKSMALI_JAR" list classes "$DEX_FILE" |
  grep -E '^(Li34/[elm];|LX/0k5r;|LX/0k7[BIXQl];|LX/0kTg;)$' ||
  true

mkdir -p "$OUT_DIR"
java -jar "$BAKSMALI_JAR" disassemble \
  --classes 'Li34/l;,Li34/e;,Li34/m;,LX/0k7B;,LX/0k7I;,LX/0k7Q;,LX/0k7X;,LX/0k7l;,LX/0k5r;,LX/0kTg;' \
  --output "$OUT_DIR" \
  "$DEX_FILE"

echo
echo "probe: disassembled files"
find "$OUT_DIR" -type f | sort
