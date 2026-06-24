#!/system/bin/sh

MODDIR="${0%/*}"
export MODDIR

# shellcheck source=/dev/null
. "$MODDIR/common/ttnet_patch.sh"

count_rule_id() {
  target="$1"

  if [ ! -f "$target" ]; then
    echo "missing"
    return 0
  fi

  grep -o '3011076' "$target" 2>/dev/null | wc -l
}

echo "[Fuck TTNet] Manual action started"
echo "[Fuck TTNet] Module dir: $MODDIR"
echo "[Fuck TTNet] Package: $PKG"

if [ ! -d "$FILES_DIR" ]; then
  echo "[Fuck TTNet] TikTok data directory not found:"
  echo "[Fuck TTNet] $FILES_DIR"
  echo "[Fuck TTNet] Open TikTok once, then run this action again."
  exit 1
fi

server_before="$(count_rule_id "$SERVER_JSON")"
config_before="$(count_rule_id "$TT_NET_CONFIG")"

echo "[Fuck TTNet] Before patch:"
echo "[Fuck TTNet] server.json rule hits: $server_before"
echo "[Fuck TTNet] tt_net_config.config rule hits: $config_before"

patch_tiktok_ttnet
result="$?"

server_after="$(count_rule_id "$SERVER_JSON")"
config_after="$(count_rule_id "$TT_NET_CONFIG")"

echo "[Fuck TTNet] After patch:"
echo "[Fuck TTNet] server.json rule hits: $server_after"
echo "[Fuck TTNet] tt_net_config.config rule hits: $config_after"

if [ "$server_after" = "0" ] && [ "$config_after" = "0" ]; then
  echo "[Fuck TTNet] Status: clean"
else
  echo "[Fuck TTNet] Status: rule still present or file missing"
fi

if [ -f "$LOG_FILE" ]; then
  echo "[Fuck TTNet] Recent module log:"
  tail -20 "$LOG_FILE"
else
  echo "[Fuck TTNet] Module log not created yet"
fi

echo "[Fuck TTNet] Manual action finished"
exit "$result"
