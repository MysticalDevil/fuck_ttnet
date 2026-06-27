#!/system/bin/sh

MODDIR="${MODDIR:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}"
export MODDIR
STATUS_SCRIPT="$MODDIR/scripts/status.sh"

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

status_field() {
  key="$1"
  printf '%s\n' "$status_output" | sed -n "s/^$key=//p" | head -n 1
}

force_stop_tiktok() {
  am force-stop "$PKG" >/dev/null 2>&1 || true
}

clear_volatile_runtime_cache() {
  rm -rf \
    "$APP_DIR/cache/"* \
    "$APP_DIR/code_cache/"* \
    "$FILES_DIR/AFRequestCache/"* \
    "$FILES_DIR/feedCache/"* \
    "$FILES_DIR/logs/"* 2>/dev/null || true
  rm -f \
    "$FILES_DIR/hostcache_v1" \
    "$FILES_DIR/hostcache_sync_v1" \
    "$FILES_DIR/foreground2.status" 2>/dev/null || true
}

echo "[Fuck TTNet] WebUI repair started"
echo "[Fuck TTNet] Module dir: $MODDIR"
echo "[Fuck TTNet] Package: $PKG"

if [ ! -d "$FILES_DIR" ]; then
  echo "[Fuck TTNet] TikTok data directory not found:"
  echo "[Fuck TTNet] $FILES_DIR"
  echo "[Fuck TTNet] Open TikTok once, then retry from WebUI."
  exit 1
fi

server_before="$(count_rule_id "$SERVER_JSON")"
config_before="$(count_rule_id "$TT_NET_CONFIG")"

echo "[Fuck TTNet] Before repair:"
echo "[Fuck TTNet] server.json rule hits: $server_before"
echo "[Fuck TTNet] tt_net_config.config rule hits: $config_before"

status_output="$(MODDIR="$MODDIR" sh "$STATUS_SCRIPT" 2>/dev/null || true)"
diagnosis_id="$(status_field diagnosis_id)"
diagnosis_title="$(status_field diagnosis_title)"
repair_action="$(status_field repair_action)"
repairability="$(status_field repairability)"
summary="$(status_field summary)"

echo "[Fuck TTNet] Diagnosis: ${diagnosis_id:-unknown} (${diagnosis_title:-Unknown})"
echo "[Fuck TTNet] Summary: ${summary:-No status summary available}"
echo "[Fuck TTNet] Planned action: ${repair_action:-none} (${repairability:-unsupported})"

result=0
case "$repair_action" in
  patch_local_ttnet)
    echo "[Fuck TTNet] Running TTNet metadata patch"
    patch_tiktok_ttnet || result="$?"
    force_stop_tiktok
    echo "[Fuck TTNet] TikTok force-stopped after patch"
    ;;
  reset_runtime_cache)
    echo "[Fuck TTNet] Clearing volatile TikTok runtime cache"
    clear_volatile_runtime_cache
    force_stop_tiktok
    echo "[Fuck TTNet] TikTok force-stopped after cache reset"
    echo "[Fuck TTNet] Note: this case is usually external to the module (proxy / TLS / CA trust)."
    ;;
  *)
    echo "[Fuck TTNet] No supported local repair for this diagnosis"
    ;;
esac

server_after="$(count_rule_id "$SERVER_JSON")"
config_after="$(count_rule_id "$TT_NET_CONFIG")"

echo "[Fuck TTNet] After repair:"
echo "[Fuck TTNet] server.json rule hits: $server_after"
echo "[Fuck TTNet] tt_net_config.config rule hits: $config_after"

status_after="$(MODDIR="$MODDIR" sh "$STATUS_SCRIPT" 2>/dev/null || true)"
final_status="$(printf '%s\n' "$status_after" | sed -n 's/^status=//p' | head -n 1)"
final_diagnosis="$(printf '%s\n' "$status_after" | sed -n 's/^diagnosis_id=//p' | head -n 1)"

if [ "$server_after" = "0" ] && [ "$config_after" = "0" ]; then
  echo "[Fuck TTNet] Status: clean"
else
  echo "[Fuck TTNet] Status: rule still present or file missing"
fi
echo "[Fuck TTNet] Final diagnosis: ${final_diagnosis:-unknown} (${final_status:-unknown})"

if [ -f "$LOG_FILE" ]; then
  echo "[Fuck TTNet] Recent module log:"
  tail -20 "$LOG_FILE"
else
  echo "[Fuck TTNet] Module log not created yet"
fi

echo "[Fuck TTNet] WebUI repair finished"
exit "$result"
